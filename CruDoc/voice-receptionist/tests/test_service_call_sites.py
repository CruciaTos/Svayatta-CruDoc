"""
Guards against call-site drift on the appointment service.

`book_appointment` gained a required `patient_name` when the CruDoc
contract was wired up, and the REST route in `api/routes/appointments.py`
went on calling it without one. That is a TypeError, but only when that
endpoint is hit -- nothing else in the suite exercises it, so every test
stayed green while a route was broken.

These checks compare the service signature against each of its callers by
parsing them, so adding the next required argument fails here rather than
in production. They are cheap and they cover the exact gap that type hints
and import-time checks do not.
"""
import ast
import inspect
import pathlib

import pytest

from app.schemas.appointment import BookingRequest
from app.services.appointment_service import book_appointment

# Arguments the callers supply from their own context rather than from a
# request body or a tool call.
_CONTEXT_ARGS = {"db", "clinic"}


def _required_params(func) -> set[str]:
    """Parameter names with no default, i.e. ones a caller must pass."""
    signature = inspect.signature(func)
    return {
        name
        for name, param in signature.parameters.items()
        if param.default is inspect.Parameter.empty
        and param.kind in (param.POSITIONAL_OR_KEYWORD, param.KEYWORD_ONLY)
    }


def _keywords_passed_to(module, callee: str) -> set[str]:
    """The keyword argument names `module` passes to `callee`."""
    source = pathlib.Path(inspect.getsourcefile(module)).read_text(encoding="utf-8")
    tree = ast.parse(source)

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        name = (
            func.id if isinstance(func, ast.Name)
            else func.attr if isinstance(func, ast.Attribute)
            else None
        )
        if name == callee:
            return {kw.arg for kw in node.keywords if kw.arg is not None}

    pytest.fail(f"No call to {callee}() found in {module.__name__}")


def test_booking_request_exposes_every_required_service_arg():
    """The REST body must be able to supply everything the service needs."""
    from_body = _required_params(book_appointment) - _CONTEXT_ARGS
    # clinic_id stands in for the resolved clinic on the REST path.
    from_body.discard("clinic_id")
    missing = from_body - set(BookingRequest.model_fields)
    assert not missing, (
        f"BookingRequest cannot supply required argument(s): {sorted(missing)}"
    )


def test_rest_route_passes_every_required_arg():
    from app.api.routes import appointments as routes_appointments

    passed = _keywords_passed_to(routes_appointments, "book_appointment")
    missing = _required_params(book_appointment) - passed
    assert not missing, (
        f"api/routes/appointments.py omits required argument(s): {sorted(missing)}"
    )


def test_voice_tool_passes_every_required_arg():
    from app.voice import tools

    passed = _keywords_passed_to(tools, "book_appointment")
    missing = _required_params(book_appointment) - passed
    assert not missing, (
        f"voice/tools.py omits required argument(s): {sorted(missing)}"
    )


def test_patient_name_is_a_required_booking_tool_argument():
    """The model must be made to collect a name, not left to volunteer one."""
    from app.voice.tools import TOOL_SCHEMAS

    schema = next(s for s in TOOL_SCHEMAS if s.name == "book_appointment")
    assert "patient_name" in schema.properties
    assert "patient_name" in schema.required
