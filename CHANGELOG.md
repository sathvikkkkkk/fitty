# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-29

Everything runs on the phone: no server and no subscription.

### Metrics

- **Recovery (1–99 %)** from HRV, resting heart rate, sleep performance and respiration
  against a personal 30-day baseline.
- **Strain (0–21)** from Banister TRIMP over heart-rate reserve, per day and per workout,
  with a daily target derived from recovery.
- **Sleep** with need, debt, performance, consistency, a composite sleep score, a stage
  hypnogram and a bedtime recommendation.
- **Stress (0–100)** estimated from daytime heart-rate elevation and overnight HRV, with an
  hourly profile.
- **Cardio load** as the 7-day vs 28-day workload ratio with an optimal weekly range.
- **Fittr Age**, a conservative biological-age estimate bounded to ±15 years of your real age.
- **Health monitor** with personal baseline bands and early-warning alerts.
- **Trends**, journal correlations, and daily Fitbit totals (steps, distance, floors,
  active zone minutes, energy burned) from the Google Health API daily roll-ups.

### Logging

- **Nutrition:** food log with calories and macros, targets from the Fitbit's measured energy
  burn (Mifflin-St Jeor fallback), energy balance, and AI meal estimates from text or a photo.
- **Workouts:** manual logging including strength exercises, sets, reps and weight
  (estimated 1RM, volume); logged sessions feed strain and cardio load.

### AI coach

- Chat about your own data with **Apple's on-device model** (free, private, no key) or
  **Claude** (your own Anthropic API key). App-computed facts and task templates keep answers
  grounded.

### App

- Black interface, English only, home-screen widget, morning recovery notification.
