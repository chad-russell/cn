// Nightly consistent copy of the live sqlite db (sweatshop.nix timer).
// Runs inside a one-off container of the app's own image (node:sqlite,
// same engine the app uses). VACUUM INTO, NOT the .backup() API —
// node:24's DatabaseSync has no .backup() (verified live 2026-11-03);
// VACUUM INTO produces the same consistent online copy and was verified
// against the live db while the app was running.
import { DatabaseSync } from 'node:sqlite'
import fs from 'node:fs'

fs.mkdirSync('/data/backups', { recursive: true })
fs.rmSync('/data/backups/nightly.db', { force: true }) // VACUUM INTO refuses to overwrite
const db = new DatabaseSync('/data/sweatshop.db')
db.exec("VACUUM INTO '/data/backups/nightly.db'")
db.close()
console.log('nightly.db:', fs.statSync('/data/backups/nightly.db').size, 'bytes')
