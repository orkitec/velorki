// SPDX-License-Identifier: AGPL-3.0-only
import type { ReactNode } from 'react';
import type { ShareRecord } from '@/share/store';
import { shareKindLabel, shareStats, shareTitle } from '@/share/format';
import styles from './share.module.css';

/**
 * Everything the share page shows around the map. Kept as a plain synchronous
 * component so it can be rendered in a test without a React Server Components
 * runtime; the map is passed in as a slot for the same reason.
 *
 * `record.name` is rider-supplied text and is escaped by React, which is what
 * replaced the relay page's hand-rolled `escapeHtml`.
 */
export default function ShareDetails({
  record,
  map,
}: {
  record: ShareRecord;
  map: ReactNode;
}) {
  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <div className={styles.kind}>{shareKindLabel(record)} shared from Velorki</div>
        <h1 className={styles.title}>{shareTitle(record)}</h1>
        <div className={styles.stats}>
          {shareStats(record).map((stat) => (
            <div className={styles.stat} key={stat.label}>
              <span className={styles.statLabel}>{stat.label}</span>
              <span className={styles.statValue}>{stat.value}</span>
            </div>
          ))}
        </div>
      </header>

      {map}

      <footer className={styles.footer}>
        <a className={`${styles.btn} ${styles.primary}`} href={`velorki://share/${record.id}`}>
          Open in Velorki
        </a>
        <a className={styles.btn} href={`/s/${record.id}.gpx`} download>
          Download GPX
        </a>
        <span className={styles.credit}>
          Map data &copy;{' '}
          <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors
        </span>
      </footer>
    </div>
  );
}
