#!/usr/bin/env python3
"""Generate docs/architecture.png for QuickBite v2.

Run:  .venv/bin/python scripts/make_architecture_diagram.py
Output: docs/architecture.png (regenerate whenever the topology changes).
"""
from __future__ import annotations

import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "architecture.png")

CREAM = "#FFF8F0"
ORANGE = "#E8830C"
DARK = "#3A2A1A"
TEAL = "#0E7C7B"
BLUE = "#2B6CB0"
GREEN = "#2F855A"
RED = "#C53030"
GREY = "#EDF2F7"
PURPLE = "#6B46C1"


def box(ax, xy, w, h, text, face, edge=DARK, fs=8, lines=None, textcolor=DARK):
    x, y = xy
    ax.add_patch(FancyBboxPatch(
        (x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.08",
        facecolor=face, edgecolor=edge, linewidth=1.4))
    ax.text(x + w / 2, y + h - 0.22, text, ha="center", va="top",
            fontsize=fs + 1, fontweight="bold", color=textcolor)
    if lines:
        for i, ln in enumerate(lines):
            ax.text(x + w / 2, y + h - 0.48 - i * 0.24, ln, ha="center",
                    va="top", fontsize=fs, color=textcolor)


def arrow(ax, p1, p2, color=DARK, style="-", lw=1.4, rad=0.0, label=None,
          lfs=7, labelpos=0.5):
    a = FancyArrowPatch(p1, p2, arrowstyle="-|>", mutation_scale=12,
                        color=color, linestyle=style, linewidth=lw,
                        connectionstyle=f"arc3,rad={rad}")
    ax.add_patch(a)
    if label:
        mx = p1[0] + (p2[0] - p1[0]) * labelpos
        my = p1[1] + (p2[1] - p1[1]) * labelpos + 0.12
        ax.text(mx, my, label, ha="center", va="bottom", fontsize=lfs,
                color=color, style="italic",
                bbox=dict(facecolor="white", edgecolor="none", pad=1))


def main() -> None:
    fig, ax = plt.subplots(figsize=(16, 9))
    ax.set_xlim(0, 16)
    ax.set_ylim(0, 9)
    ax.axis("off")
    fig.patch.set_facecolor("white")
    ax.set_facecolor("white")

    ax.text(8, 8.55, "QuickBite v2 — System Architecture",
            ha="center", fontsize=16, fontweight="bold", color=DARK)
    ax.text(8, 8.22, "FastAPI + PostgreSQL (transactional outbox) + RabbitMQ + 4 workers + Flutter",
            ha="center", fontsize=9, color="#666666")

    # --- left: clients -----------------------------------------------------
    box(ax, (0.4, 5.4), 2.4, 2.0, "Flutter app", CREAM, ORANGE,
        lines=["screens §5", "Idempotency-Key", "persisted (prefs)"])
    box(ax, (0.4, 3.1), 2.4, 2.0, "FastAPI api", "#FFF3E0", ORANGE, fs=8,
        lines=["POST /api/v1/orders → 202", "JWT auth + RBAC", "server-side totals"])

    # --- postgres ----------------------------------------------------------
    box(ax, (4.0, 5.4), 3.0, 2.0, "PostgreSQL 16", "#EBF8FF", BLUE,
        lines=["orders, order_items", "order_status_history", "idempotency_records"])
    box(ax, (4.0, 3.1), 3.0, 2.0, "outbox / retry tables", "#EBF8FF", BLUE,
        lines=["outbox_events (pending→sent)", "retry_jobs (scheduled→done)", "quarantine_records"])

    # --- rabbitmq ----------------------------------------------------------
    box(ax, (8.4, 5.9), 3.2, 1.5, "quickbite.orders", "#F0FFF4", GREEN,
        lines=["durable TOPIC exchange"])
    box(ax, (8.4, 3.6), 3.2, 1.5, "quickbite.dead", "#FFF5F5", RED,
        lines=["durable DIRECT exchange",
               'orders.dead-letter.queue ← "failed"'])

    # --- workers -----------------------------------------------------------
    box(ax, (12.8, 6.6), 2.8, 1.15, "payment worker", "#FAF5FF", PURPLE, fs=8,
        lines=["order.created → PAID"])
    box(ax, (12.8, 5.3), 2.8, 1.15, "restaurant worker", "#FAF5FF", PURPLE, fs=8,
        lines=["order.paid → CONFIRMED"])
    box(ax, (12.8, 4.0), 2.8, 1.15, "delivery worker", "#FAF5FF", PURPLE, fs=8,
        lines=["order.confirmed → DRIVER_ASSIGNED"])
    box(ax, (12.8, 2.7), 2.8, 1.15, "notification worker", "#FAF5FF", PURPLE, fs=8,
        lines=["order.# → notifications"])

    # --- infra processes ---------------------------------------------------
    box(ax, (4.0, 1.15), 3.0, 1.35, "outbox dispatcher", "#E6FFFA", TEAL, fs=8,
        lines=["SKIP LOCKED claim lease", "confirms + mandatory"])
    box(ax, (8.4, 1.15), 3.2, 1.35, "retry scheduler", "#E6FFFA", TEAL, fs=8,
        lines=["scheduled → pending", "targeted redelivery"])

    # --- arrows: checkout path ---------------------------------------------
    arrow(ax, (2.8, 4.6), (4.0, 4.6), ORANGE, lw=1.8, label="checkout tx")
    arrow(ax, (5.5, 5.4), (5.5, 5.1), BLUE, lw=1.4, label="outbox row", lfs=6.5)
    arrow(ax, (7.0, 4.4), (8.4, 6.4), TEAL, lw=1.6, rad=0.15, label="publish")
    # exchange -> workers
    arrow(ax, (11.6, 6.9), (12.8, 7.17), GREEN, lw=1.3, label="order.created", lfs=6.5)
    arrow(ax, (11.6, 6.45), (12.8, 5.87), GREEN, lw=1.3, label="order.paid", lfs=6.5)
    arrow(ax, (11.6, 6.0), (12.8, 4.57), GREEN, lw=1.3, label="order.confirmed", lfs=6.5)
    arrow(ax, (11.6, 5.9), (12.8, 3.45), GREEN, lw=1.3, rad=-0.25, label="order.#", lfs=6.5)
    # workers -> dead exchange
    arrow(ax, (14.2, 6.6), (11.0, 4.35), RED, style="--", lw=1.2, rad=0.3,
          label="exhausted → failed", lfs=6.5)
    # scheduler -> dispatcher loop
    arrow(ax, (8.4, 1.8), (7.0, 1.8), TEAL, lw=1.3, label="promote due", lfs=6.5)
    # workers read/write db
    arrow(ax, (12.8, 6.9), (7.0, 6.9), PURPLE, style="--", lw=1.0, rad=0.12,
          label="tx: transition + child outbox", lfs=6.5)
    # dispatcher claim arrow
    arrow(ax, (5.5, 3.1), (5.5, 2.5), BLUE, style="--", lw=1.1, label="claim", lfs=6.5)

    # --- legend -------------------------------------------------------------
    ax.text(0.4, 0.55, "Legend:", fontsize=8, fontweight="bold", color=DARK)
    legend = [
        ("solid", DARK, "request / publish flow"),
        ("dashed", PURPLE, "database read/write"),
        ("solid", RED, "quarantine path"),
        ("solid", TEAL, "outbox / retry plumbing"),
    ]
    for i, (st, c, txt) in enumerate(legend):
        x0 = 1.5 + i * 3.6
        ax.plot([x0, x0 + 0.7], [0.55, 0.55], color=c,
                linestyle="-" if st == "solid" else "--", linewidth=1.6)
        ax.text(x0 + 0.85, 0.55, txt, fontsize=7.5, va="center", color=DARK)

    ax.text(8, 0.15,
            "State machine: PENDING → PAID → CONFIRMED → DRIVER_ASSIGNED (success) | "
            "PAYMENT_FAILED / FAILED (terminal). Retries: 1 + 3 delayed (2s/10s/30s), then quarantine.",
            ha="center", fontsize=7.5, color="#666666")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    fig.savefig(OUT, dpi=150, bbox_inches="tight")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    sys.exit(main())
