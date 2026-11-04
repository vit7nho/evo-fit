"""Importa todos os models para registrá-los no metadata (usado pelo Alembic e pelos testes)."""

from app.db.base import Base
from app.modules.activities.models import Activity, CyclingDetails, EnduranceDetails, SwimDetails
from app.modules.auth.models import RefreshToken
from app.modules.exercises.models import Exercise, ExerciseMuscle, MuscleGroupRow
from app.modules.goals.models import Goal
from app.modules.plans.models import PlanSession, TrainingPlan
from app.modules.sessions.models import SessionExercise, SetEntry, WorkoutSession
from app.modules.training.models import ExerciseGroup, TemplateItem, WorkoutTemplate
from app.modules.users.models import User, UserConsent, UserProfile

__all__ = [
    "Activity",
    "Base",
    "CyclingDetails",
    "EnduranceDetails",
    "Exercise",
    "ExerciseGroup",
    "ExerciseMuscle",
    "Goal",
    "MuscleGroupRow",
    "PlanSession",
    "RefreshToken",
    "SessionExercise",
    "SetEntry",
    "SwimDetails",
    "TemplateItem",
    "TrainingPlan",
    "User",
    "UserConsent",
    "UserProfile",
    "WorkoutSession",
    "WorkoutTemplate",
]
