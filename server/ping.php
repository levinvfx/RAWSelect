<?php
// RAW Select – ehemaliger Nutzungs-Ping, seit 21.10.2026 stillgelegt (Levins Entscheid: nur noch
// Downloads zählen, die App sammelt nichts mehr).
// Ab Version 2.0 sendet die App keinen Ping mehr. Ältere Versionen (bis 2.0 Beta 1) melden sich weiter,
// bis sie aktualisiert sind. Dieser Endpunkt nimmt die Meldung an, liest sie nicht und speichert nichts.
// 204 statt 404: die alte App merkt sich einen Erfolg und versucht es nicht bei jedem Start erneut.
// Die bis dahin gespeicherten Zeilen in /var/lib/rawselect/usage.sqlite bleiben unangetastet
// (Löschung nur mit Levins OK).

http_response_code(204);
