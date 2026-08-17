from bot import build_ivr_menu_prompt, route_ivr_choice


def test_build_ivr_menu_prompt_contains_expected_routes():
    prompt = build_ivr_menu_prompt()

    assert 'Press 1 to book an appointment' in prompt
    assert 'Press 2 to speak to a receptionist' in prompt
    assert 'Press 0 to repeat this menu' in prompt


def test_route_ivr_choice_maps_digits_to_actions():
    assert route_ivr_choice('1') == 'book_appointment'
    assert route_ivr_choice('2') == 'transfer_to_receptionist'
    assert route_ivr_choice('0') == 'repeat_menu'
    assert route_ivr_choice('9') == 'unknown'
