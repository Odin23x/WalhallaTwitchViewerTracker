# Walhalla Twitch Viewer Tracker
### Touch Portal Plugin by odin23x

Zeigt die aktuelle Zuschauerliste deines Twitch-Kanals in Touch Portal an.

## Einstellungen
| Einstellung | Beschreibung |
|---|---|
| Twitch Client ID | Deine App Client ID (dev.twitch.tv) |
| Twitch OAuth Token | OAuth Token (mit oder ohne `oauth:` Präfix) |
| Broadcaster User ID | Deine numerische Twitch User ID |
| Update Interval Seconds | Aktualisierungsintervall (10–300, Standard: 30) |

### Benötigte Token-Scopes
- `moderator:read:chatters`

## States
| State | Beschreibung |
|---|---|
| Zuschauer Liste | Alle aktuellen Zuschauer (einer pro Zeile) |
| Anzahl Zuschauer | Anzahl der aktuellen Zuschauer |
| Status | Plugin-Status / Fehlermeldung |
| Letztes Update | Zeitstempel der letzten Aktualisierung |

## Aktionen
- **Refresh now** – Sofortige Aktualisierung

## Lizenz
MIT License – by odin23x
