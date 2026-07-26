"""
Day 5: question templates for the Knowledge Capture Agent's guided
voice interview. Static per-equipment-kind scripts rather than a
dynamically generated flow — predictable, reviewable questions matter
more here than novelty, since the person answering is often a retiring
senior engineer whose time is the scarce resource we're protecting.
"""
from typing import List, Optional

DEFAULT_QUESTIONS = [
    "What do you check first when this equipment shows abnormal behavior?",
    "What's the most common failure you've seen on equipment like this?",
    "Is there a step in the manual that's often skipped but shouldn't be?",
    "Who else should be called if this fails during a night shift?",
]

EQUIPMENT_QUESTIONS = {
    "PUMP": [
        "What do you check first when this pump vibrates abnormally?",
        "How do you tell bearing wear apart from cavitation on this pump?",
        "What's the safe shutdown sequence if you suspect seal failure?",
        "Who should be paged if this pump trips during a night shift?",
    ],
    "VALVE": [
        "What's the first sign this valve is about to stick or fail?",
        "How do you verify a leak is from the packing versus the seat?",
        "What torque or pressure range is safe for manual override here?",
        "Who has the most experience with this valve's history?",
    ],
    "COMPRESSOR": [
        "What do unusual vibration or noise levels usually indicate here?",
        "What's the correct sequence for an emergency shutdown?",
        "Which sensor reading do you trust least on this unit, and why?",
        "Who should be called for a compressor issue overnight?",
    ],
    "TANK": [
        "What early signs suggest a tank inspection should be moved up?",
        "How do you distinguish corrosion from normal wear here?",
        "What's the safe procedure for a suspected level-sensor fault?",
        "Who verifies tank integrity sign-off before it's cleared?",
    ],
    "MOTOR": [
        "What's the earliest warning sign this motor is overheating?",
        "How do you distinguish a bearing issue from an electrical fault?",
        "What's the safe restart procedure after a thermal trip?",
        "Who should review vibration logs before a motor is cleared?",
    ],
    "BOILER": [
        "What's the first check when pressure readings look abnormal?",
        "What's a near-miss you've seen here that never made it into a report?",
        "What's the safe isolation sequence before internal inspection?",
        "Who has the deepest history with this specific boiler?",
    ],
    "TURBINE": [
        "What vibration pattern would make you stop this turbine immediately?",
        "What's commonly misdiagnosed on this equipment, in your experience?",
        "What's the correct spin-down procedure in an emergency?",
        "Who should be consulted before any blade-related work?",
    ],
    "CONVEYOR": [
        "What's the first sign a belt is about to fail here?",
        "How do you tell alignment drift from bearing wear on this unit?",
        "What's the safe lockout procedure before clearing a jam?",
        "Who's handled the most incidents on this conveyor line?",
    ],
}


def get_questions_for_equipment(equipment_id: Optional[str]) -> List[str]:
    if not equipment_id:
        return DEFAULT_QUESTIONS
    kind = equipment_id.split("-")[0].upper()
    return EQUIPMENT_QUESTIONS.get(kind, DEFAULT_QUESTIONS)