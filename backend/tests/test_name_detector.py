"""Unit tests for the PHI name/ID heuristic detector."""
import pytest

from parser_api.services.name_detector import detect, should_flag, DetectedName


# ---------------------------------------------------------------------------
# detect()
# ---------------------------------------------------------------------------


def test_detect_israeli_id_number():
    text = "ת.ז. 123456789 — בדיקת דם"
    matches = detect(text)
    assert any(m.pattern_type == "id_number" for m in matches)


def test_detect_name_field_hebrew():
    text = "שם: כהן יצחק — ביקור 2024"
    matches = detect(text)
    assert any(m.pattern_type == "name_field" for m in matches)


def test_detect_mrn():
    text = "מספר תיק: 987654 — סיכום ביקור"
    matches = detect(text)
    assert any(m.pattern_type == "mrn" for m in matches)


def test_detect_no_phi():
    text = "בדיקת המוגלובין: 14.2 g/dL — תקין"
    matches = detect(text)
    assert matches == []


def test_detect_deduplicates_same_id():
    text = "ת.ז. 123456789 ו-ת.ז. 123456789"
    matches = detect(text)
    id_matches = [m for m in matches if m.pattern_type == "id_number"]
    assert len(id_matches) == 1  # same number deduplicated


def test_detect_multiple_distinct():
    text = "ת.ז. 111111111 שם: לוי דוד ת.ז. 222222222"
    matches = detect(text)
    assert len(matches) >= 2


# ---------------------------------------------------------------------------
# should_flag()
# ---------------------------------------------------------------------------


def test_should_flag_with_two_patterns():
    text = "ת.ז. 123456789 שם: ישראל ישראלי — ביקור"
    flagged, reason = should_flag(text)
    assert flagged is True
    assert reason  # non-empty explanation


def test_should_not_flag_single_pattern():
    text = "ת.ז. 123456789 — בדיקת דם"
    flagged, _ = should_flag(text)
    assert flagged is False


def test_should_not_flag_clean_text():
    text = "מגנזיום: 0.9 mmol/L — גבול תחתון תקין"
    flagged, _ = should_flag(text)
    assert flagged is False


def test_should_flag_with_id_and_mrn():
    text = "מספר זהות 987654321 מספר תיק: 654321"
    flagged, reason = should_flag(text)
    assert flagged is True
    assert "2 PHI patterns" in reason or "patterns detected" in reason
