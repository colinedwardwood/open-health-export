Status widget extension for the small and medium system families. The exporter
writes one versioned, health-value-free snapshot per destination to an App
Group container and reloads the widget after a terminal run. Widget timelines
precompute stale and overdue transitions, plus two daily overdue-age entries,
so status can worsen without another app wake. Thresholds remain absent until
R-71 supplies a measured value; manual destinations do not invent one.
