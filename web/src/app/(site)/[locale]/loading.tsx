// SPDX-License-Identifier: AGPL-3.0-only
/** The static shell while a page streams in. Deliberately quiet. */
export default function Loading() {
  return (
    <div className="shell py-24" aria-busy="true">
      <div className="h-3 w-24 rounded-full bg-panel-2" />
      <div className="mt-6 h-10 w-2/3 max-w-xl rounded-full bg-panel-2" />
      <div className="mt-4 h-4 w-full max-w-2xl rounded-full bg-panel-2" />
    </div>
  );
}
