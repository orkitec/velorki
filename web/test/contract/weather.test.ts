// SPDX-License-Identifier: AGPL-3.0-only
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { parse } from 'yaml';
import { POST as weather } from '@/app/(api)/weather/route';
import { AUTH, jsonRequest, withEnv } from '../helpers';

/**
 * POST /weather against its contract in openapi.yaml. The app's tests copy
 * the yaml's examples, so they are held to the schemas here, and so is a real
 * answer of the route.
 *
 * The checker knows the keywords the app's checker knows
 * (`app/test/support/openapi_schema.dart`) and fails on any other, so a schema
 * that passes here can be read there.
 */

type Schema = Record<string, unknown>;
const doc = parse(readFileSync(join(process.cwd(), 'openapi.yaml'), 'utf8')) as Schema;

function at(path: string): Schema {
  return path.split('/').reduce<Schema>((node, key) => node[key] as Schema, doc);
}

const ANNOTATIONS = new Set(['description', 'default', 'examples', 'example', 'format']);

function isType(value: unknown, type: string): boolean {
  switch (type) {
    case 'object':
      return typeof value === 'object' && value !== null && !Array.isArray(value);
    case 'array':
      return Array.isArray(value);
    case 'string':
      return typeof value === 'string';
    case 'number':
      return typeof value === 'number';
    case 'integer':
      return Number.isInteger(value);
    case 'boolean':
      return typeof value === 'boolean';
    case 'null':
      return value === null;
    default:
      throw new Error(`type ${type}`);
  }
}

function check(schema: Schema, value: unknown, path: string, problems: string[]): void {
  const obj = value as Record<string, unknown>;
  for (const [key, arg] of Object.entries(schema)) {
    if (ANNOTATIONS.has(key)) continue;
    switch (key) {
      case '$ref':
        check(at((arg as string).slice(2)), value, path, problems);
        break;
      case 'type':
        if (!isType(value, arg as string)) {
          problems.push(`${path} is not ${String(arg)}`);
          return;
        }
        break;
      case 'required':
        for (const name of arg as string[]) if (!(name in obj)) problems.push(`${path}.${name} missing`);
        break;
      case 'properties':
        for (const [name, sub] of Object.entries(obj)) {
          const s = (arg as Record<string, Schema>)[name];
          if (s !== undefined) check(s, sub, `${path}.${name}`, problems);
        }
        break;
      case 'additionalProperties': {
        if (arg !== false) break;
        const known = Object.keys((schema.properties as Schema | undefined) ?? {});
        for (const name of Object.keys(obj)) if (!known.includes(name)) problems.push(`${path}.${name} not allowed`);
        break;
      }
      case 'items':
        (value as unknown[]).forEach((item, i) => {
          check(arg as Schema, item, `${path}[${String(i)}]`, problems);
        });
        break;
      case 'enum':
        if (!(arg as unknown[]).includes(value)) problems.push(`${path} not in enum`);
        break;
      case 'minimum':
        if ((value as number) < (arg as number)) problems.push(`${path} below ${String(arg)}`);
        break;
      case 'maximum':
        if ((value as number) > (arg as number)) problems.push(`${path} above ${String(arg)}`);
        break;
      case 'maxItems':
        if ((value as unknown[]).length > (arg as number)) problems.push(`${path} too long`);
        break;
      case 'pattern':
        if (!new RegExp(arg as string).test(value as string)) problems.push(`${path} does not match`);
        break;
      case 'oneOf': {
        const matches = (arg as Schema[]).filter((option) => {
          const sub: string[] = [];
          check(option, value, path, sub);
          return sub.length === 0;
        });
        if (matches.length !== 1) problems.push(`${path} matches ${String(matches.length)} of oneOf`);
        break;
      }
      default:
        throw new Error(`schema keyword "${key}" at ${path}`);
    }
  }
}

function problemsOf(schema: string, value: unknown): string[] {
  const problems: string[] = [];
  check({ $ref: `#/components/schemas/${schema}` }, value, schema, problems);
  return problems;
}

function operation(): Schema {
  return (doc.paths as Record<string, Schema>)['/weather']?.post as Schema;
}

function examples(content: Schema): Record<string, unknown> {
  const json = (content.content as Record<string, Schema>)['application/json'];
  return Object.fromEntries(
    Object.entries((json?.examples ?? {}) as Record<string, { value: unknown }>).map(([k, v]) => [k, v.value]),
  );
}

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe('POST /weather contract', () => {
  it('has request and response examples that match the schemas', () => {
    const op = operation();
    const requests = examples(op.requestBody as Schema);
    const answers = examples((op.responses as Record<string, Schema>)['200'] as Schema);
    expect(Object.keys(requests)).not.toHaveLength(0);
    expect(Object.keys(answers)).not.toHaveLength(0);
    for (const value of Object.values(requests)) expect(problemsOf('WeatherRequest', value)).toEqual([]);
    for (const value of Object.values(answers)) expect(problemsOf('WeatherResponse', value)).toEqual([]);
  });

  it('answers the request example with a body that matches the schema', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(Date.parse('2026-10-10T20:30:00Z'));
    const fixture = (name: string) =>
      readFileSync(join(process.cwd(), 'test/fixtures/weather', name), 'utf8');
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: string) => {
        const url = new URL(input);
        const name =
          url.host === 'api.met.no'
            ? 'metno-complete.json'
            : url.searchParams.has('source_id')
              ? 'brightsky-station.json'
              : 'brightsky-berlin.json';
        return new Response(fixture(name), { headers: { 'content-type': 'application/json' } });
      }),
    );
    const [request] = Object.values(examples(operation().requestBody as Schema));
    await withEnv({}, async () => {
      const res = await weather(jsonRequest('https://api.velorki.com/weather', request, AUTH));
      expect(res.status).toBe(200);
      const body = (await res.json()) as { cells: { hours: unknown[] }[] };
      expect(problemsOf('WeatherResponse', body)).toEqual([]);
      expect(body.cells.map((c) => c.hours.length)).toEqual([2, 2]);
    });
  });
});
