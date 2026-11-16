from factorio_mcp.instructions import INSTRUCTIONS


def test_instructions_cover_rules():
    text = INSTRUCTIONS.lower()
    assert "only your own inventory" in text
    assert "do not invent" in text
    assert "server_status" in text
