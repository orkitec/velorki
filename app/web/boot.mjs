// SPDX-License-Identifier: AGPL-3.0-only
// index.html's one script, a file of its own so the Content-Security-Policy
// (_headers) needs no inline scripts.
import { boot } from './device_gate.mjs';

boot(window);
