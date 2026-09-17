// SPDX-License-Identifier: AGPL-3.0-only
import styles from './s/[id]/share.module.css';

/** Unknown and expired share links land here; links live for 365 days. */
export default function ShareNotFound() {
  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <div className={styles.kind}>Velorki</div>
        <h1 className={styles.title}>This link is no longer available</h1>
      </header>
      <div className={styles.mapError}>
        Shared routes and rides expire after a year. Ask for a fresh link.
      </div>
    </div>
  );
}
