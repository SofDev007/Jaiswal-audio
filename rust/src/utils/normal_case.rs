/// ALL-CAPS song titles ("TUM HI HO (FROM \"AASHIQUI 2\")") become Title Case.
/// Titles with any lowercase letter, caseless scripts (Hindi, Japanese…) and
/// short all-caps titles like "DNA" are left alone.
/// ponytail: acronyms inside a long caps title ("BTS") come out as "Bts";
/// add a keep-list if that shows up. Same rule as `normalCase()` in Dart.
pub fn normal_case(s: String) -> String {
    let letters = s.chars().filter(|c| c.is_alphabetic()).count();
    if letters < 4 || s.chars().any(char::is_lowercase) || !s.chars().any(char::is_uppercase) {
        return s;
    }
    let mut out = String::with_capacity(s.len());
    let mut prev: Option<char> = None;
    for c in s.chars() {
        let word_start = prev.map_or(true, |p| !p.is_alphanumeric() && p != '\'');
        if word_start {
            out.extend(c.to_uppercase());
        } else {
            out.extend(c.to_lowercase());
        }
        prev = Some(c);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::normal_case;

    #[test]
    fn caps_titles_become_title_case() {
        let n = |s: &str| normal_case(s.to_string());
        assert_eq!(n("TUM HI HO"), "Tum Hi Ho");
        assert_eq!(n("DON'T STOP (FROM \"ANIMAL\")"), "Don't Stop (From \"Animal\")");
        assert_eq!(n("DNA"), "DNA");
        assert_eq!(n("Tum Hi Ho"), "Tum Hi Ho");
        assert_eq!(n("iPhone LOVE"), "iPhone LOVE");
        assert_eq!(n("तुम ही हो"), "तुम ही हो");
    }
}
