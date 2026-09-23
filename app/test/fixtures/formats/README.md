# Format fixtures

Real GPX, FIT and TCX files from openly licensed sources, plus a few written
or generated here, for the codec packages (`packages/velorki_gpx`,
`packages/velorki_fit`, `packages/velorki_tcx`) and the app's import and
export tests. Every file is under 300 kB; the ones marked *trimmed* are the
original with track points cut after the first N of every segment or lap,
nothing else changed.

Files from the Garmin FIT SDK are not here: the FIT Protocol License forbids
redistributing the SDK's contents, samples included. The FIT course with
course points is generated with `package:fit_sdk` instead (see below), because
no device-written course file was found under a licence compatible with this
repository. Files under CC-BY-SA (firefly-cpp/tcx-test-files) and files of
unknown licence (ThomasKuehne/FIT-test-files, Wikipedia's GPX sample) were
left out.

`packages/velorki_fit/test/fixtures/garmin_edge820_ride.fit` and
`test/features/import_export/fixtures/activity.fit` are copies of
`fit/fitparse_garmin_edge820_ride.fit` below.

## Licences

| Source | Licence | Files |
|---|---|---|
| [tkrajina/gpxpy](https://github.com/tkrajina/gpxpy) `test_files/` | Apache-2.0 | `gpxpy_*.gpx` |
| [sudhanshuraheja/go-garmin-gpx](https://github.com/sudhanshuraheja/go-garmin-gpx) `samples/` | Apache-2.0 | `gogarmin_*.gpx` |
| [viewmygpx sample files](https://www.viewmygpx.com/sample-gpx-files/) | CC0 | `viewmygpx_*.gpx` |
| [msimms/TestFilesForFitnessApps](https://github.com/msimms/TestFilesForFitnessApps) | MIT | `msimms_*` |
| [dtcooper/python-fitparse](https://github.com/dtcooper/python-fitparse) `tests/files/` | MIT (repository licence; the files were contributed to that test set by its users) | `fitparse_*.fit` |
| [aaron-schroeder/activereader](https://github.com/aaron-schroeder/activereader) `tests/` | MIT | `activereader_*.tcx` |
| written here | AGPL-3.0-only, like the repository | `handwritten_*` |
| generated here with `package:fit_sdk` | AGPL-3.0-only | `generated_*` |

## GPX

| File | Source | Exercises |
|---|---|---|
| `gpxpy_runkeeper_hr.gpx` | gpxpy `gpx_with_garmin_extension.gpx` | Runkeeper export whose one point is a `<wpt>` with time, elevation and a `gpxtpx:hr` extension, no track |
| `gpxpy_all_fields.gpx` | gpxpy `gpx1.1_with_all_fields.gpx` | every GPX 1.1 element: two `<trk>`, two `<rte>` with `<rtept>` name/sym/type, `<wpt>` with sym, type and `<link>`, metadata links |
| `gpxpy_route.gpx` | gpxpy `route.gpx` | a `<rte>` of 55 named `<rtept>` |
| `gpxpy_brouter.gpx` | gpxpy `brouter_with_link.gpx` | a BRouter export with a `<link>` |
| `gogarmin_hr_cad_atemp.gpx` | go-garmin-gpx `extensions.gpx` | `gpxtpx:hr`, `cad` and `atemp` in one point, a `gpxx:WaypointExtension` |
| `gogarmin_geotours_waypoints.gpx` | go-garmin-gpx `StLouisZoo.gpx` | ten `<wpt>` with `<sym>` and `<link>`, metadata author and links |
| `viewmygpx_sensors_trimmed.gpx` | viewmygpx `extensions-test.gpx`, first 600 of 1200 points | a cycling ride with `gpxtpx:hr`, `cad` and `atemp` on every point |
| `viewmygpx_multi_track_trimmed.gpx` | viewmygpx `multi-day-hike.gpx`, first 150 points of each of the 4 tracks | four named `<trk>` in one file, five `<wpt>` with name and sym |
| `viewmygpx_geocaching_waypoints.gpx` | viewmygpx `geocaching-pocket-query.gpx` | fifteen `<wpt>` with sym and type, no track |
| `msimms_garmin_connect_run.gpx` | TestFilesForFitnessApps `gpx/run_03_garmin.gpx` | Garmin Connect export, `ns3:` prefix, heart rate |
| `msimms_runkeeper_run.gpx` | TestFilesForFitnessApps `gpx/20180831_beach_run_runkeeper.gpx` | Runkeeper export without extensions |
| `handwritten_gpxdata_power.gpx` | written here after the pytrainer wiki sample | ClueTrust `gpxdata:hr`, `cadence`, `temp` and `power`, one point with both gpxdata and gpxtpx, a zero power, a point without temperature |

## FIT

| File | Source | Exercises |
|---|---|---|
| `fitparse_garmin_edge820_ride.fit` | python-fitparse `garmin-edge-820-bike.fit` | Garmin Edge 820: heart rate, cadence, temperature per record, lap and session with calories |
| `fitparse_wahoo_elemnt_bolt_devdata.fit` | python-fitparse `elemnt-bolt-no-application-id-inside-developer-data-id.fit` | Wahoo ELEMNT BOLT: power and temperature, developer data without an application id, session totals |
| `fitparse_garmin_edge500_ride_laps.fit` | python-fitparse `sample-activity.fit` | Garmin Edge 500, 88.8 km, four laps, session totals (2045 kcal, 299 m ascent), temperature |
| `fitparse_garmin_indoor_trainer_laps_power.fit` | python-fitparse `sample-activity-indoor-trainer.fit` | five laps, power, heart rate, cadence, temperature, no positions |
| `msimms_wahoo_elemnt_ride_power.fit` | TestFilesForFitnessApps `fit/20191117_bike_wahoo_elemnt.fit` | Wahoo ELEMNT ride with GPS, power, cadence, temperature |
| `msimms_zwift_ride_power.fit` | TestFilesForFitnessApps `fit/20210218_zwift_bike_race.fit` | Zwift virtual ride: power, heart rate, cadence, temperature, calories |
| `generated_course_with_course_points.fit` | generated here | a course file: `course`, `lap`, six `record`s and five `course_point`s (generic, left, water, right, generic) with names and distances |

## TCX

| File | Source | Exercises |
|---|---|---|
| `activereader_forerunner220_run.tcx` | activereader `tests/testdata.tcx` | Garmin Forerunner 220 activity: four laps with calories, heart rate, run cadence and speed in `ns3:TPX` |
| `msimms_garmin_edge705_ride_trimmed.tcx` | TestFilesForFitnessApps `tcx/20111211_trail_ride_garmin_edge_705.tcx`, first 500 of 1410 points | Garmin Edge 705 ride from Garmin Connect: `Sport="Biking"`, altitude and distance per point |
| `handwritten_cycling_watts.tcx` | written here | a cycling activity: two laps, heart rate, cadence, `ns3:Watts` and `Speed`, lap `ns3:LX` extension |
| `handwritten_course.tcx` | written here | a `<Course>` with a lap, six track points and four `<CoursePoint>`s (Generic, Left, Water, Right) with notes |
