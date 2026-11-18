#!/usr/bin/env python3
"""Бюджет ошибок и пороги сжигания.

Использование:
  error_budget.py 99.9                  # бюджет простоя за 30 дней
  error_budget.py 99.5 --days 28
  error_budget.py 99 --events 30        # событийный SLI: 30 запусков за окно
  error_budget.py 99.9 --bad-rate 0.02  # текущая доля ошибок -> burn rate и сколько жить бюджету
"""
import argparse


def fmt_minutes(m: float) -> str:
    if m >= 60:
        h, mm = divmod(m, 60)
        return f"{int(h)} ч {mm:.0f} мин"
    return f"{m:.1f} мин"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("slo", type=float, help="цель в процентах, например 99.9")
    ap.add_argument("--days", type=float, default=30.0, help="окно SLO, дней")
    ap.add_argument("--events", type=int, help="число событий за окно (для событийного SLI)")
    ap.add_argument("--bad-rate", type=float, help="текущая доля плохих событий, 0..1")
    a = ap.parse_args()
    if not 0 < a.slo < 100:
        raise SystemExit("SLO должен быть между 0 и 100")
    budget_frac = 1 - a.slo / 100
    window_min = a.days * 24 * 60
    print(f"SLO {a.slo}% за {a.days:g} дн.: бюджет {budget_frac:.4%} = "
          f"{fmt_minutes(budget_frac * window_min)} простоя")
    if a.events:
        allowed = budget_frac * a.events
        print(f"событий за окно {a.events}: допустимо плохих {allowed:.2f}"
              + (" — ни одного провала; удлини окно или снизь цель" if allowed < 1 else ""))
    print("пороги алертов (SRE Workbook):")
    for share, hours, label in ((0.02, 1, "будить"), (0.05, 6, "будить"), (0.10, 72, "тикет")):
        rate = share * (a.days * 24) / hours
        print(f"  {share:.0%} бюджета за {hours} ч → burn rate {rate:.1f}, доля ошибок "
              f"{rate * budget_frac:.3%} — {label}")
    if a.bad_rate is not None:
        rate = a.bad_rate / budget_frac
        left = (a.days * 24) / rate if rate > 0 else float("inf")
        print(f"текущая доля ошибок {a.bad_rate:.3%}: burn rate {rate:.1f}; "
              f"весь бюджет сгорит за {left:.1f} ч")


if __name__ == "__main__":
    main()
