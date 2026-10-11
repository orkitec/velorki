// SPDX-License-Identifier: AGPL-3.0-only
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { forecastSource, parseRows } from '@/weather/dwd';
import { metnoPoint, parseTimeseries } from '@/weather/metno';
import { parseGrid } from '@/weather/nws';
import { durationHours, intervalHours, isoHour, lerpAngle } from '@/weather/time';

const fixture = (name: string): unknown =>
  JSON.parse(readFileSync(join(process.cwd(), 'test/fixtures/weather', name), 'utf8'));

describe('ISO-8601 durations', () => {
  it('reads the forms forecast intervals use, in whole hours', () => {
    expect(durationHours('PT1H')).toBe(1);
    expect(durationHours('PT2H')).toBe(2);
    expect(durationHours('P1D')).toBe(24);
    expect(durationHours('P1DT6H')).toBe(30);
    expect(durationHours('P7DT12H')).toBe(180);
    expect(durationHours('PT90M')).toBe(2);
    expect(durationHours('P1W')).toBe(168);
  });

  it('refuses what is not one, and anything under half an hour', () => {
    for (const bad of ['', 'P', 'PT', '1H', 'P1Y', 'P1M', 'PT1H30', 'PT10M']) {
      expect(durationHours(bad), bad).toBeUndefined();
    }
  });

  it('expands an interval to the start of each hour it spans', () => {
    expect(intervalHours('2026-10-10T13:00:00+00:00/PT3H').map(isoHour)).toEqual([
      '2026-10-10T13:00:00Z',
      '2026-10-10T14:00:00Z',
      '2026-10-10T15:00:00Z',
    ]);
    expect(intervalHours('2026-10-10T22:00:00+00:00/P1DT6H')).toHaveLength(30);
    expect(intervalHours('2026-10-10T13:00:00+00:00')).toEqual([]);
    expect(intervalHours('garbage/PT1H')).toEqual([]);
  });
});

describe('interpolation', () => {
  it('turns a direction the short way round', () => {
    expect(lerpAngle(350, 10, 0.5)).toBeCloseTo(0);
    expect(lerpAngle(10, 350, 0.25)).toBeCloseTo(5);
    expect(lerpAngle(90, 180, 0.5)).toBeCloseTo(135);
  });
});

describe('NWS grid', () => {
  it('drops a series in a unit it does not know', () => {
    const grid = fixture('nws-grid.json') as { properties: { windSpeed: { uom: string } } };
    grid.properties.windSpeed.uom = 'wmoUnit:furlong_fortnight-1';
    expect(parseGrid(grid)).toEqual([]);
  });

  it('converts Fahrenheit', () => {
    const grid = fixture('nws-grid.json') as {
      properties: { temperature: { uom: string; values: { value: number }[] } };
    };
    grid.properties.temperature.uom = 'wmoUnit:degF';
    for (const v of grid.properties.temperature.values) v.value = 50;
    expect(parseGrid(grid)[0]?.temp).toBeCloseTo(10);
  });
});

describe('Bright Sky', () => {
  it('picks the nearest forecast source and ignores observations', () => {
    expect(forecastSource(fixture('brightsky-berlin.json') as never)).toBe(2382);
    expect(forecastSource(fixture('brightsky-no-forecast.json') as never)).toBeUndefined();
  });

  it('uses only that source’s rows, and none past the last', () => {
    const points = parseRows(fixture('brightsky-berlin.json') as never, 2382);
    expect(points.map((p) => isoHour(p.t))).toEqual([
      '2026-10-10T19:00:00Z',
      '2026-10-10T20:00:00Z',
      '2026-10-10T21:00:00Z',
      '2026-10-10T22:00:00Z',
      '2026-10-10T23:00:00Z',
      '2026-10-11T00:00:00Z',
      '2026-10-11T01:00:00Z',
      '2026-10-11T02:00:00Z',
    ]);
    // 19:00 is the forecast's, not the 6150 observation's 10.9.
    expect(points[0]?.temp).toBe(10.6);
  });
});

describe('MET Norway', () => {
  it('snaps to 0.025° in the Nordic model and 0.1° elsewhere', () => {
    expect(metnoPoint({ lat: 59.925, lon: 10.775 })).toEqual({ lat: 59.925, lon: 10.775 });
    expect(metnoPoint({ lat: 35.675, lon: 139.725 })).toEqual({ lat: 35.7, lon: 139.7 });
    expect(metnoPoint({ lat: -33.875, lon: 151.2 })).toEqual({ lat: -33.9, lon: 151.2 });
  });

  it('splits six hours of precipitation evenly and invents nothing after the last step', () => {
    const points = parseTimeseries(fixture('metno-complete.json'));
    const six = points.filter((p) => p.t >= Date.parse('2026-10-11T06:00:00Z'));
    expect(six).toHaveLength(6);
    expect(six.reduce((sum, p) => sum + p.precip, 0)).toBeCloseTo(1.8);
    expect(isoHour(points.at(-1)?.t ?? 0)).toBe('2026-10-11T11:00:00Z');
  });

  it('falls back to next_6_hours where an hour has no next_1_hours', () => {
    const body = {
      properties: {
        timeseries: [
          {
            time: '2026-10-10T18:00:00Z',
            data: {
              instant: { details: { air_temperature: 5, wind_speed: 2, wind_from_direction: 90 } },
              next_6_hours: { details: { precipitation_amount: 3 } },
            },
          },
        ],
      },
    };
    expect(parseTimeseries(body)).toEqual([
      {
        t: Date.parse('2026-10-10T18:00:00Z'),
        temp: 5,
        wind: 2,
        windDir: 90,
        gust: null,
        precip: 0.5,
        precipProb: null,
        cloud: null,
      },
    ]);
  });
});
