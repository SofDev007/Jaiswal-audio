/// Turns an exception or a raw plugin error into text fit for the screen.
///
/// Raw errors (a source's JSON error body, "SocketException: Failed host
/// lookup ...", Rust "error sending request for url ...") must never reach
/// the UI: log them, show this instead. A network failure gets the "no
/// internet" text, anything else the caller's plain [fallback].
String friendlyError(Object? error, {required String fallback}) =>
    isNetworkError(error) ? noInternetMessage : fallback;

const noInternetMessage = 'No internet connection. Connect and try again.';

/// True when [error] looks like the device couldn't reach the server
/// (offline, DNS, refused/reset/timed-out connection, TLS handshake).
bool isNetworkError(Object? error) {
  if (error == null) return false;
  final s = error.toString().toLowerCase();
  return _networkHints.any(s.contains);
}

const _networkHints = [
  'socketexception',
  'failed host lookup',
  'no address associated',
  'network is unreachable',
  'network unreachable',
  'no route to host',
  'connection refused',
  'connection reset',
  'connection closed',
  'connection aborted',
  'connection timed out',
  'connection failed',
  'timed out',
  'timeoutexception',
  'handshakeexception',
  'clientexception',
  'error sending request',
  'dns error',
  'tcp connect error',
  'os error 7',
  'os error 101',
  'os error 111',
];
