// SPDX-License-Identifier: AGPL-3.0-only
// The handful of glyphs the site needs, inline so nothing is fetched and the
// content-security policy needs no image host. All are decorative: the label
// next to them carries the meaning.
import type { SVGProps } from 'react';

type IconProps = SVGProps<SVGSVGElement>;

function Icon({ children, ...props }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false" {...props}>
      {children}
    </svg>
  );
}

export function GitHubIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path
        fill="currentColor"
        d="M12 .5a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.37-3.88-1.37-.53-1.35-1.3-1.7-1.3-1.7-1.05-.72.08-.71.08-.71 1.17.08 1.78 1.2 1.78 1.2 1.03 1.78 2.7 1.27 3.36.97.1-.75.4-1.27.73-1.56-2.56-.29-5.25-1.28-5.25-5.7 0-1.26.45-2.29 1.19-3.1-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.18 1.18a11 11 0 0 1 5.8 0c2.2-1.5 3.17-1.18 3.17-1.18.63 1.59.24 2.76.12 3.05.74.81 1.18 1.84 1.18 3.1 0 4.43-2.69 5.4-5.26 5.69.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .5Z"
      />
    </Icon>
  );
}

export function AppleIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path
        fill="currentColor"
        d="M16.37 12.63c.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.71-3.19-1.73-1.36-.14-2.65.8-3.34.8-.69 0-1.75-.78-2.88-.76-1.48.02-2.85.86-3.61 2.19-1.54 2.67-.39 6.62 1.11 8.79.73 1.06 1.6 2.25 2.75 2.2 1.1-.04 1.52-.71 2.86-.71 1.33 0 1.71.71 2.88.69 1.19-.02 1.94-1.08 2.67-2.14.84-1.23 1.19-2.42 1.2-2.48-.02-.01-2.31-.89-2.33-3.54ZM14.2 6.2c.6-.74 1.01-1.76.9-2.78-.87.04-1.93.58-2.56 1.31-.56.65-1.05 1.69-.92 2.68.97.08 1.96-.49 2.58-1.21Z"
      />
    </Icon>
  );
}

export function GooglePlayIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path fill="currentColor" d="M3.6 2.3c-.23.24-.36.6-.36 1.07v17.26c0 .47.13.83.36 1.07l.09.08 9.67-9.67v-.23L3.69 2.22l-.09.08Z" />
      <path fill="currentColor" d="m16.6 15.36-3.24-3.25v-.23l3.24-3.24.07.04 3.84 2.18c1.1.62 1.1 1.64 0 2.27l-3.84 2.18-.07.05Z" />
      <path fill="currentColor" d="m16.67 15.31-3.31-3.31-9.76 9.76c.36.39.96.43 1.64.05l11.43-6.5Z" opacity=".85" />
      <path fill="currentColor" d="M16.67 8.69 5.24 2.19c-.68-.39-1.28-.34-1.64.05l9.76 9.76 3.31-3.31Z" opacity=".7" />
    </Icon>
  );
}

export function CheckIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" d="m5 12.5 4.5 4.5L19 7" />
    </Icon>
  );
}

export function DashIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" d="M6 12h12" />
    </Icon>
  );
}

export function ArrowIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <path fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" d="M5 12h13m-5.5-6 6 6-6 6" />
    </Icon>
  );
}

export function GlobeIcon(props: IconProps) {
  return (
    <Icon {...props}>
      <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeWidth="1.8" />
      <path fill="none" stroke="currentColor" strokeWidth="1.8" d="M3 12h18M12 3c2.5 2.6 2.5 15.4 0 18M12 3c-2.5 2.6-2.5 15.4 0 18" />
    </Icon>
  );
}

/** The route glyph from the app icon, used as the wordmark's mark. */
export function VelorkiMark(props: IconProps) {
  return (
    <svg viewBox="0 0 1024 1024" width="28" height="28" aria-hidden="true" focusable="false" {...props}>
      <path d="M296 716 Q 360 400 728 308" fill="none" stroke="currentColor" strokeWidth="96" strokeLinecap="round" />
      <circle cx="296" cy="716" r="118" fill="currentColor" />
      <circle cx="728" cy="308" r="118" fill="currentColor" />
    </svg>
  );
}
