# Significant Place Mining Starts With DBSCAN

Status: accepted

The first implementation of Riconoscimento dei Luoghi Significativi should cluster place evidence with DBSCAN after extracting candidate visits from raw GPS traces and compatible diary stops. We considered more adaptive density-based variants, but DBSCAN is the better starting point because it is easier to explain, easier to tune around a fixed spatial threshold such as 75 meters, and already matches the product rule that a place becomes automatically confirmed only after recurring evidence across distinct days.
