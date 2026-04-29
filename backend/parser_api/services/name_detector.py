"""
Hebrew PHI name heuristic detector.
Flags documents that appear to contain more than one patient's PHI.

Strategy: look for structured PHI patterns in the OCR text:
  - Israeli ID numbers (9-digit sequences): ת.ז. / מספר זהות / ID
  - Full-name markers: שם: / שם מלא: / מטופל: / חולה: followed by Hebrew text
  - Israeli medical record numbers (6-8 digit sequences near MRN keywords)

Returns a list of pattern matches.  The caller flags the document when len >= 2 distinct names.
"""
import re
from dataclasses import dataclass


@dataclass
class DetectedName:
    pattern_type: str   # "id_number" | "name_field" | "mrn"
    snippet: str        # up to 40 chars of context


# Compiled patterns (module-level for reuse across calls)
_ID_RE = re.compile(
    r"(?:ת\.ז\.?|מספר\s+זהות|ID\s*:?)\s*(\d{7,9})\b",
    re.IGNORECASE,
)
_NAME_FIELD_RE = re.compile(
    r"(?:שם(?:\s+מלא)?|מטופל|חולה|patient|name)\s*:?\s*"
    r"([֐-׿]{2,}\s+[֐-׿]{2,}(?:\s+[֐-׿]{2,})?)",
    re.IGNORECASE,
)
_MRN_RE = re.compile(
    r"(?:מס(?:פר)?\s*(?:תיק|רפואי)|MRN|chart\s*#?)\s*:?\s*(\d{5,8})\b",
    re.IGNORECASE,
)


def detect(text: str) -> list[DetectedName]:
    """
    Scan `text` for PHI name/ID patterns.
    Returns all distinct matches.
    """
    found: list[DetectedName] = []
    seen: set[str] = set()

    for m in _ID_RE.finditer(text):
        key = f"id:{m.group(1)}"
        if key not in seen:
            seen.add(key)
            found.append(DetectedName("id_number", text[max(0, m.start()-10):m.end()+10]))

    for m in _NAME_FIELD_RE.finditer(text):
        key = f"name:{m.group(1).strip().lower()}"
        if key not in seen:
            seen.add(key)
            found.append(DetectedName("name_field", text[max(0, m.start()-5):m.end()+20]))

    for m in _MRN_RE.finditer(text):
        key = f"mrn:{m.group(1)}"
        if key not in seen:
            seen.add(key)
            found.append(DetectedName("mrn", text[max(0, m.start()-10):m.end()+10]))

    return found


def should_flag(text: str) -> tuple[bool, str]:
    """
    Returns (flag: bool, reason: str).
    Flags when 2+ distinct PHI patterns are found (suggests multiple patients).
    """
    matches = detect(text)
    if len(matches) >= 2:
        snippets = "; ".join(f"[{m.pattern_type}] {m.snippet[:30]}" for m in matches[:3])
        return True, f"{len(matches)} PHI patterns detected: {snippets}"
    return False, ""
