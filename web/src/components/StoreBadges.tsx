// SPDX-License-Identifier: AGPL-3.0-only
import { useTranslations } from 'next-intl';
import { GITHUB_URL, STORE_URL_ANDROID, STORE_URL_IOS } from '@/site/config';
import { AppleIcon, GitHubIcon, GooglePlayIcon } from './Icons';

/**
 * The store buttons. A store whose URL is not configured is left out of the
 * markup entirely rather than rendered as a dead link; GitHub is always there,
 * because the source and the release APKs always are.
 */
export function StoreBadges({ className }: { className?: string }) {
  const t = useTranslations('home.hero');
  const hasStore = STORE_URL_IOS !== '' || STORE_URL_ANDROID !== '';
  return (
    <div className={className}>
      <ul className="flex flex-wrap gap-3">
        {STORE_URL_IOS !== '' && (
          <li>
            <a href={STORE_URL_IOS} rel="noreferrer" className="btn btn-secondary">
              <AppleIcon />
              {t('storeIos')}
            </a>
          </li>
        )}
        {STORE_URL_ANDROID !== '' && (
          <li>
            <a href={STORE_URL_ANDROID} rel="noreferrer" className="btn btn-secondary">
              <GooglePlayIcon />
              {t('storeAndroid')}
            </a>
          </li>
        )}
        <li>
          <a href={GITHUB_URL} rel="noreferrer" className={hasStore ? 'btn btn-secondary' : 'btn btn-primary'}>
            <GitHubIcon />
            {t('storeGithub')}
          </a>
        </li>
      </ul>
      {!hasStore && <p className="mt-3 max-w-md text-sm text-muted">{t('storesPending')}</p>}
    </div>
  );
}
