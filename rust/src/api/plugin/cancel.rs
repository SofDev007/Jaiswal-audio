//! Cancellation of content-importer requests, per plugin.
//!
//! Each plugin has a cancel generation, bumped by [`request`]. A request notes
//! the generation when it is submitted ([`ticket`]) and, once it holds the
//! plugin's lock, records it as the running one ([`begin`]). The importer's
//! HTTP host function polls [`is_cancelled`], which is true once a cancel
//! arrived after the running request was submitted:
//!
//! - a request cancelled while it waited for the lock never runs;
//! - a running request's current and next HTTP calls fail at once, so the
//!   plugin returns and the lock is released;
//! - a request submitted after the cancel starts from the new generation and
//!   runs normally, so a new import can start straight away.
//!
//! This is cooperative: WebAssembly code that loops without making an HTTP
//! call cannot be interrupted (the runtime has no fuel or epoch limits).

use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::Mutex;

/// The error a cancelled request's HTTP calls (and the request) return.
pub const CANCELLED: &str = "Cancelled by the app";

#[derive(Default)]
struct State {
    generation: u64,
    running: Option<u64>,
}

static STATE: Lazy<Mutex<HashMap<String, State>>> = Lazy::new(Default::default);

fn with<R>(plugin_id: &str, f: impl FnOnce(&mut State) -> R) -> R {
    let mut map = STATE.lock().unwrap_or_else(|e| e.into_inner());
    f(map.entry(plugin_id.to_string()).or_default())
}

/// Cancels the request running on [plugin_id] and any already waiting for it.
pub fn request(plugin_id: &str) {
    with(plugin_id, |s| s.generation += 1);
}

/// Taken when a request is submitted, before it waits for the plugin's lock.
pub fn ticket(plugin_id: &str) -> u64 {
    with(plugin_id, |s| s.generation)
}

/// Marks [ticket]'s request as running. False if it was cancelled while it
/// waited, in which case it must not run.
pub fn begin(plugin_id: &str, ticket: u64) -> bool {
    with(plugin_id, |s| {
        if s.generation > ticket {
            return false;
        }
        s.running = Some(ticket);
        true
    })
}

/// The running request has finished.
pub fn end(plugin_id: &str) {
    with(plugin_id, |s| s.running = None);
}

/// Whether the request running on [plugin_id] has been cancelled.
pub fn is_cancelled(plugin_id: &str) -> bool {
    with(plugin_id, |s| matches!(s.running, Some(t) if s.generation > t))
}

/// Calls [`end`] when dropped, so a request that errors or panics still
/// clears its running mark.
pub struct Running(pub String);

impl Drop for Running {
    fn drop(&mut self) {
        end(&self.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_cancel_stops_the_running_request_only() {
        let id = "cancel-test-running";
        let t = ticket(id);
        assert!(begin(id, t));
        assert!(!is_cancelled(id));
        request(id);
        assert!(is_cancelled(id));
        end(id);
        assert!(!is_cancelled(id), "nothing is running after end");
    }

    #[test]
    fn a_request_cancelled_while_waiting_never_runs() {
        let id = "cancel-test-waiting";
        let queued = ticket(id);
        request(id);
        assert!(!begin(id, queued));
    }

    #[test]
    fn a_request_after_the_cancel_runs_normally() {
        let id = "cancel-test-after";
        request(id);
        let fresh = ticket(id);
        assert!(begin(id, fresh));
        assert!(!is_cancelled(id));
        end(id);
    }

    #[test]
    fn plugins_are_independent() {
        let (a, b) = ("cancel-test-a", "cancel-test-b");
        assert!(begin(a, ticket(a)));
        assert!(begin(b, ticket(b)));
        request(a);
        assert!(is_cancelled(a));
        assert!(!is_cancelled(b));
        end(a);
        end(b);
    }

    #[test]
    fn the_running_guard_clears_the_mark() {
        let id = "cancel-test-guard";
        assert!(begin(id, ticket(id)));
        {
            let _running = Running(id.to_string());
            request(id);
            assert!(is_cancelled(id));
        }
        assert!(!is_cancelled(id));
    }
}
