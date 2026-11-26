"""Conta de demonstração (Fase 6, ADR-065): `demo@evofit.local` com 8 semanas de uso.

Uso (na pasta services/api, com o banco de desenvolvimento ligado):

    .venv/Scripts/python.exe -m app.demo_seed [--password "frase de quatro palavras"]

Sem --password (nem DEMO_PASSWORD no ambiente), gera uma frase e mostra uma vez.
Rodar de novo apaga a conta de demonstração e cria tudo outra vez, terminando no dia
de hoje: rode na manhã da apresentação. Só a conta `demo@evofit.local` é tocada, e
nunca com APP_ENV=production.

Os dados passam pelas rotas da própria API, num cliente dentro do processo, com o
relógio de cada serviço levado ao dia do registro: as mesmas validações e os mesmos
cálculos do app (recordes, estímulo, planos, totais). Todos são fictícios: a conta se
chama "Demo", usa o domínio `evofit.local` e os alimentos levam "(exemplo)" no nome.
"""

from __future__ import annotations

import argparse
import os
import secrets
import sys
from collections.abc import Iterator
from contextlib import ExitStack, contextmanager
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from unittest import mock
from zoneinfo import ZoneInfo

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Environment, get_settings
from app.modules.exercises.seed import global_exercise_id
from app.modules.goals import service as goal_service
from app.modules.nutrition import service as nutrition_service
from app.modules.plans import service as plan_service
from app.modules.sessions import service as session_service
from app.modules.users.models import User

EMAIL = "demo@evofit.local"
NAME = "Demo"
TZ = ZoneInfo("America/Sao_Paulo")
WEEKS = 8
API = "/api/v1"
WORDS = [
    "abacate",
    "barco",
    "cadeira",
    "dente",
    "escada",
    "farol",
    "girafa",
    "janela",
    "lago",
    "mesa",
    "navio",
    "ovelha",
    "piano",
    "quadro",
    "remo",
    "sino",
    "tigre",
    "uva",
    "vento",
    "zebra",
    "caneca",
    "trilha",
    "nuvem",
    "pedra",
]


class SeedError(RuntimeError):
    """A API recusou um passo do seed; a mensagem traz a resposta."""


def ex(slug: str) -> str:
    return str(global_exercise_id(slug))


# --- fichas: (exercício, séries, repetições, carga inicial, aumento a cada 2 semanas) ---


@dataclass(frozen=True)
class Item:
    slug: str
    sets: int
    reps: int
    load: float | None
    step: float = 0
    seconds: int | None = None  # exercício por tempo (prancha)
    group: int | None = None


TEMPLATES: dict[str, tuple[str, list[Item]]] = {
    "A": (
        "Treino A — Peito, ombros e tríceps",
        [
            Item("supino-reto-barra", 3, 8, 60, 2.5),
            Item("supino-inclinado-halteres", 3, 10, 22, 2),
            Item("crucifixo-halteres", 3, 12, 14, 0, group=0),
            Item("triceps-corda", 3, 12, 25, 2.5, group=0),
            Item("elevacao-lateral-halteres", 3, 15, 8, 1),
        ],
    ),
    "B": (
        "Treino B — Costas e bíceps",
        [
            Item("puxada-frontal", 3, 10, 55, 2.5),
            Item("remada-curvada-barra", 3, 8, 50, 2.5),
            Item("remada-unilateral-halter", 3, 10, 26, 2),
            Item("rosca-direta-barra", 3, 10, 25, 2.5),
            Item("rosca-martelo", 3, 12, 12, 1),
        ],
    ),
    "C": (
        "Treino C — Pernas e abdômen",
        [
            Item("agachamento-livre", 3, 8, 70, 5),
            Item("leg-press", 3, 12, 160, 10),
            Item("mesa-flexora", 3, 12, 40, 2.5),
            Item("elevacao-pelvica", 3, 10, 60, 5),
            Item("prancha", 3, 0, None, seconds=45),
        ],
    ),
}
# Segunda A, quarta B, sexta C. Corridas na terça, quinta e sábado (plano de 10 km nas
# últimas 3 semanas); caminhada em alguns domingos. Panturrilhas e antebraços ficam sem
# exercício próprio, para o Meu Corpo mostrar o que ficou para trás.
STRENGTH_DAYS = {0: "A", 2: "B", 4: "C"}
RUN_DAYS = (1, 5)
PLAN_WEEKDAYS = [1, 3, 5]
PLAN_WEEKS = 3
SKIPPED = {(3, 4), (5, 2)}  # (semana, dia da semana) sem treino: a vida acontece

# --- alimentos (por 100 g, valores aproximados de exemplo) ---

FOODS = {
    "arroz": ("Arroz branco cozido (exemplo)", 128, 2.5, 28.1, 0.2),
    "feijao": ("Feijão carioca cozido (exemplo)", 76, 4.8, 13.6, 0.5),
    "frango": ("Peito de frango grelhado (exemplo)", 159, 32, 0, 2.5),
    "ovo": ("Ovo cozido (exemplo)", 146, 13.3, 0.6, 9.5),
    "aveia": ("Aveia em flocos (exemplo)", 394, 13.9, 66.6, 8.5),
    "banana": ("Banana prata (exemplo)", 98, 1.3, 26, 0.1),
    "iogurte": ("Iogurte natural (exemplo)", 51, 4.1, 1.9, 3),
    "pao": ("Pão integral (exemplo)", 253, 9.4, 49.9, 3.7),
    "batata": ("Batata-doce cozida (exemplo)", 77, 0.6, 18.4, 0.1),
}
# Um dia completo dá ~2.650 kcal e ~190 g de proteína, perto das metas (2.600 e 150 g).
MEALS = {
    "breakfast": (7, [("aveia", 80), ("banana", 120), ("iogurte", 170)]),
    "lunch": (12, [("arroz", 300), ("feijao", 200), ("frango", 200)]),
    "snack": (16, [("pao", 100), ("ovo", 100), ("banana", 100)]),
    "dinner": (20, [("batata", 350), ("frango", 200), ("arroz", 150)]),
}


class Seeder:
    def __init__(self, client: TestClient, today: date) -> None:
        self.client = client
        self.today = today
        self.start = today - timedelta(weeks=WEEKS)
        self.headers: dict[str, str] = {}
        self.clock = datetime.combine(self.start, time(7), TZ)
        self.templates: dict[str, str] = {}
        self.foods: dict[str, str] = {}

    # --- infraestrutura ---

    def call(self, method: str, path: str, expected: int = 200, **kwargs) -> dict:
        response = self.client.request(method, f"{API}{path}", headers=self.headers, **kwargs)
        if response.status_code != expected:
            raise SeedError(f"{method} {path}: {response.status_code} {response.text[:300]}")
        return response.json() if response.content else {}

    @contextmanager
    def frozen(self) -> Iterator[None]:
        """Leva o relógio dos serviços para `self.clock` (dia e hora do registro)."""
        with ExitStack() as stack:
            stack.enter_context(
                mock.patch.object(session_service, "_now", lambda: self.clock.astimezone(UTC))
            )
            for module in (plan_service, nutrition_service, goal_service):
                stack.enter_context(
                    mock.patch.object(module, "_today", lambda user: self.clock.date())
                )
            yield

    def at(self, day: date, hour: int, minute: int = 0) -> None:
        self.clock = datetime.combine(day, time(hour, minute), TZ)

    def days(self) -> Iterator[tuple[int, date]]:
        for offset in range((self.today - self.start).days):
            day = self.start + timedelta(days=offset)
            yield offset // 7, day

    # --- passos ---

    def account(self, password: str) -> None:
        body = {"email": EMAIL, "password": password, "display_name": NAME, "accept_terms": True}
        tokens = self.call("POST", "/auth/register", 201, json=body)
        self.headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        self.call("PUT", "/me/consents/health_data")
        self.call("PUT", "/me/consents/ai_processing")
        profile = {
            "timezone": "America/Sao_Paulo",
            "experience_level": "intermediate",
            "weekly_availability": {"days_per_week": 5, "minutes_per_session": 60},
            "primary_objective": "gain_muscle",
            "secondary_objectives": ["run"],
            "preferred_modalities": ["strength", "run", "walk"],
            "equipment": ["gym"],
            "onboarding_completed": True,
        }
        self.call("PATCH", "/me", json=profile)

    def plans_and_foods(self) -> None:
        for key, (name, items) in TEMPLATES.items():
            body = {
                "name": name,
                "items": [
                    {
                        "exercise_id": ex(i.slug),
                        "planned_sets": [
                            {"duration_s": i.seconds} if i.seconds else {"reps_min": i.reps}
                        ]
                        * i.sets,
                        "rest_s": 90,
                        **({"group": i.group} if i.group is not None else {}),
                    }
                    for i in items
                ],
                "groups": [{"kind": "biset", "rest_after_s": 90}] if key == "A" else [],
            }
            self.templates[key] = self.call("POST", "/workout-templates", 201, json=body)["id"]
        for key, (name, kcal, protein, carbs, fat) in FOODS.items():
            body = {"name": name, "kcal": kcal, "protein_g": protein, "carbs_g": carbs}
            body["fat_g"] = fat
            self.foods[key] = self.call("POST", "/foods", 201, json=body)["id"]

    def goals(self) -> None:
        start = self.start.isoformat()
        for body in (
            {
                "kind": "strength",
                "title": "Supino reto com 80 kg",
                "target": {"exercise": "Supino reto com barra", "load_kg": 80, "reps": 5},
                "start_date": start,
                "target_date": (self.today + timedelta(weeks=12)).isoformat(),
            },
            {
                "kind": "weight_gain",
                "title": "Chegar a 77 kg",
                "target": {"target_weight_kg": 77},
                "start_date": start,
            },
            {
                "kind": "frequency",
                "title": "Treinar 4 vezes por semana",
                "target": {"sessions_per_week": 4},
                "start_date": start,
            },
        ):
            self.call("POST", "/goals", 201, json=body)
        done = self.call(
            "POST",
            "/goals",
            201,
            json={
                "kind": "run_distance",
                "title": "Correr 5 km",
                "target": {"distance_km": 5},
                "start_date": start,
            },
        )
        self.call("PATCH", f"/goals/{done['id']}", json={"status": "achieved"})

    def workout(self, week: int, day: date, key: str) -> None:
        self.at(day, 18, 30)
        session = self.call(
            "POST", "/workout-sessions", 201, json={"template_id": self.templates[key]}
        )
        level = week // 2
        for index, item in enumerate(TEMPLATES[key][1]):
            entry = session["exercises"][index]["id"]
            path = f"/workout-sessions/{session['id']}/exercises/{entry}/sets"
            if index == 0:
                self.clock += timedelta(minutes=3)
                warmup = {"kind": "warmup", "reps": 10, "load_kg": round(item.load * 0.5)}
                self.call("POST", path, 201, json=warmup)
            last = None
            for _ in range(item.sets):
                self.clock += timedelta(minutes=3)
                if item.seconds:
                    body: dict = {"duration_s": item.seconds + 5 * level}
                else:
                    body = {"reps": item.reps, "load_kg": item.load + item.step * level}
                last = self.call("POST", path, 201, json=body)
            # Drop set no fim do supino, nas semanas pares.
            if key == "A" and index == 0 and week % 2 == 1 and last is not None:
                self.clock += timedelta(minutes=1)
                drop = {
                    "kind": "drop",
                    "parent_set_id": last["id"],
                    "reps": 6,
                    "load_kg": round((item.load + item.step * level) * 0.7),
                }
                self.call("POST", path, 201, json=drop)
        self.clock += timedelta(minutes=5)
        self.call(
            "POST",
            f"/workout-sessions/{session['id']}/finish",
            json={"perceived_effort": 7 + week % 2},
        )

    def run(self, day: date, seconds: int, km: float, hour: int = 7) -> str:
        self.at(day, hour)
        body = {
            "modality": "run",
            "started_at": self.clock.isoformat(),
            "duration_s": seconds,
            "distance_m": round(km * 1000),
            "perceived_effort": 6,
        }
        return self.call("POST", "/activities", 201, json=body)["id"]

    def walk(self, day: date) -> None:
        self.at(day, 9)
        body = {
            "modality": "walk",
            "started_at": self.clock.isoformat(),
            "duration_s": 45 * 60,
            "distance_m": 4200,
        }
        self.call("POST", "/activities", 201, json=body)

    def training(self) -> None:
        plan_start = self.today - timedelta(weeks=PLAN_WEEKS)
        plan_start += timedelta(days=(1 - plan_start.weekday()) % 7)  # uma terça
        for week, day in self.days():
            weekday = day.weekday()
            if (week, weekday) in SKIPPED:
                continue
            if weekday in STRENGTH_DAYS:
                self.workout(week, day, STRENGTH_DAYS[weekday])
            elif day < plan_start and weekday in RUN_DAYS:
                # Antes do plano: 5 a 6 km, com o ritmo melhorando de 6:10 para 5:40 /km.
                km = 5 + (week % 3) * 0.5
                pace = 370 - 4 * week
                self.run(day, round(km * pace), km)
            elif weekday == 6 and week % 2 == 1:
                self.walk(day)
        # O plano de 10 km, começado há 3 semanas; as sessões já passadas ganham a corrida.
        self.at(plan_start, 6)
        with self.frozen():
            plan = self.call(
                "POST",
                "/training-plans",
                201,
                json={"kind": "run_10k", "weekdays": PLAN_WEEKDAYS, "start_date": None},
            )
        for session in plan["sessions"]:
            day = date.fromisoformat(session["scheduled_date"])
            if day >= self.today:
                # Sem faltas no plano: a primeira sessão sem corrida é a "próxima" do Início.
                continue
            minutes = session["total_s"] / 60
            km = round(minutes / 5.6, 1)  # ~5:36 /km
            activity = self.run(day, session["total_s"], km, hour=6)
            self.call(
                "PUT",
                f"/training-plans/{plan['id']}/sessions/{session['id']}/activity",
                json={"activity_id": activity},
            )

    def nutrition_and_body(self) -> None:
        self.at(self.today - timedelta(days=8), 8)
        targets = {"kcal": 2600, "protein_g": 150, "carbs_g": 330, "fat_g": 75}
        with self.frozen():
            self.call("PUT", "/nutrition/targets", json=targets)
        for back in range(7, -1, -1):
            day = self.today - timedelta(days=back)
            for meal_type, (hour, items) in MEALS.items():
                if back == 0 and meal_type != "breakfast":
                    continue  # hoje, só o café da manhã
                body = {
                    "eaten_at": f"{day.isoformat()}T{hour:02d}:00:00",
                    "meal_type": meal_type,
                    # Um pouco de variação entre os dias (de -6% a +6%).
                    "items": [
                        {
                            "food_id": self.foods[f],
                            "quantity_g": round(g * (1 + (back % 5 - 2) * 0.03)),
                        }
                        for f, g in items
                    ],
                }
                self.call("POST", "/meals", 201, json=body)
        # Peso toda segunda de manhã: de 74,0 a ~75,8 kg; cintura a cada 4 semanas.
        for week in range(WEEKS + 1):
            day = self.start + timedelta(weeks=week)
            if day >= self.today:
                break
            body: dict = {
                "measured_at": f"{day.isoformat()}T07:00:00",
                "weight_kg": round(74 + 0.23 * week + (0.2 if week % 3 == 2 else 0), 1),
            }
            if week % 4 == 0:
                body["waist_cm"] = 81 + week * 0.1
                body["arm_cm"] = 34 + week * 0.1
            self.call("POST", "/body-measurements", 201, json=body)

    def run_all(self, password: str) -> None:
        self.at(self.start, 7)
        with self.frozen():
            self.account(password)
            self.plans_and_foods()
            self.goals()
        with self.frozen():
            self.training()
        self.nutrition_and_body()


def remove_demo(db: Session) -> bool:
    """Apaga a conta de demonstração (cascata); só ela, identificada pelo e-mail."""
    user = db.scalar(select(User).where(User.email == EMAIL))
    if user is None:
        return False
    db.delete(user)
    db.commit()
    return True


def passphrase() -> str:
    return " ".join(secrets.choice(WORDS) for _ in range(4))


def seed(app: FastAPI, db: Session, password: str, today: date | None = None) -> dict:
    """Recria a conta de demonstração terminando em `today` (padrão: hoje em São Paulo)."""
    if get_settings().app_env == Environment.PRODUCTION:
        raise SeedError("O seed de demonstração não roda com APP_ENV=production.")
    replaced = remove_demo(db)
    today = today or datetime.now(TZ).date()
    with TestClient(app) as client:
        Seeder(client, today).run_all(password)
    return {"email": EMAIL, "replaced": replaced, "from": today - timedelta(weeks=WEEKS)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Recria a conta de demonstração do EvoFit.")
    parser.add_argument("--password", help="senha da conta (padrão: DEMO_PASSWORD ou gerada)")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    password = args.password or os.environ.get("DEMO_PASSWORD") or ""
    generated = not password
    password = password or passphrase()

    from app.db.session import get_session_factory
    from app.main import app

    with get_session_factory()() as db:
        try:
            result = seed(app, db, password)
        except SeedError as error:
            print(f"Erro: {error}", file=sys.stderr)
            return 1
    action = "recriada" if result["replaced"] else "criada"
    print(f"Conta de demonstração {action}: {result['email']}")
    print(f"Dados de {result['from']:%d/%m/%Y} até hoje.")
    if generated:
        print(f"Senha (gerada agora, anote): {password}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
