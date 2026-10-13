# deploy_agent

This is my shell script for deploying the Student Attendance Tracker. `deploy_agent.sh` can deploy the app, run it, and archive its logs. It also handles Ctrl+C / Ctrl+Z if you interrupt it during the deploy. I didn't change `attendance_checker.py` at all.

## What's in the repo

```
deploy_agent.sh      the script
README.md            this file
.gitignore           keeps test projects and zips out of git
templates/           the 3 original files (not modified)
    attendance_checker.py
    assets.csv
    config.json
```

You need `python3` and `zip` installed. The script checks for both before deploying.

## How to run it

First make it executable (only needed once):

```bash
chmod +x deploy_agent.sh
```

I made it work two ways, a menu or arguments.

**Menu:** just run it with nothing after it.

```bash
./deploy_agent.sh
```

```
1) Deploy the application
2) Run the application
3) Archive the logs
4) Exit
```

**Arguments:** if you want to skip the menu.

```bash
./deploy_agent.sh deploy          # feature 1
./deploy_agent.sh run demo        # feature 2
./deploy_agent.sh archive demo    # feature 3
```

`demo` is the name you gave the project when deploying (the folder is `attendance_tracker_demo`). If you leave the name out, the script shows the deployed projects and asks which one.

## Feature 1: Deploy

1. Checks that `python3` and `zip` are installed (and prints the Python version). If one is missing it stops with an error. It also checks that the 3 template files exist.
2. Asks for a project name and creates `attendance_tracker_<name>/`. The name can only have letters, numbers, `-` and `_`. If the folder already exists it asks if you want to overwrite it. If you say no, it stops and nothing is touched.
3. Creates `Helpers/` and `reports/`, copies `attendance_checker.py` and `config.json` from `templates/`, and then asks how to build `assets.csv`:
   - **A** copies the header plus however many students you want from `templates/assets.csv`.
   - **B** makes a new roster from a list of names inside the script, with all counts at 0. If you ask for more than 10 students, the extra ones are called "Student 11", "Student 12", etc.
4. Runs `chmod +x` on `attendance_checker.py` and `chmod 600` on `config.json` so only the owner can read or change the thresholds.
5. Asks if you want to change the thresholds (explained below).
6. Checks all the files and folders are there and then starts the app, which is how I know the deploy worked.

If something fails in the middle (like a permission error), the half-made folder is deleted.

### total_sessions

`total_sessions` has to be one more than the sessions already in the roster, because it includes today.

- **Option A:** the template students already have 4 sessions each, so `total_sessions` stays at **5** like in the original config.
- **Option B:** the new students have 0 sessions, so today is session 1. The script uses `sed` to set `total_sessions` to **1**.

## Updating the thresholds

The script asks if you want to update the thresholds. If you answer `y`:

- It asks for the warning value (Enter keeps 75) and then the failure value (Enter keeps 50).
- The input has to be a whole number from 0 to 100. If you type something like `abc` or `150` it says it's invalid and asks again, so `sed` only ever gets a real number.
- Warning has to be higher than failure, otherwise it asks for both again.
- Then `sed` replaces only the numbers on the `"warning":` and `"failure":` lines:

```bash
sed -i.bak "s/\"warning\": *[0-9]*/\"warning\": $warning/" Helpers/config.json
```

Nothing else in the file changes. I used `-i.bak` and then delete the `.bak` file because plain `sed -i` works differently on Mac and Linux.

## Feature 2: Run

Goes into the project folder and runs `python3 attendance_checker.py`. The app is interactive, so you mark each student present or absent. It writes `reports/attendance.log` and `reports/absent.log`.

## Feature 3: Archiving the logs

The script checks `reports/` for `attendance.log` and `absent.log`, and moves each one into its own folder with the date and time in the name:

```
attendance_tracker_demo/
└── archives/
    ├── attendance/
    │   └── attendance_20261013_143022.log
    └── absent/
        └── absent_20261013_143022.log
```

The timestamp comes from `date +%Y%m%d_%H%M%S`, so every archived file has a different name. It prints where each log went. If a log doesn't exist (for example nobody was absent so there's no `absent.log`), it just says it's skipping it and keeps going.

I move the logs instead of copying them, so the next session starts with empty logs.

## Ctrl+C and Ctrl+Z

While deploying, the script traps both signals:

```bash
trap 'cleanup "Ctrl+C"' INT
trap 'cleanup "Ctrl+Z"' TSTP
```

When you press either one, `cleanup`:

1. Ignores any more Ctrl+C presses so the cleanup can finish.
2. Prints that the deployment was interrupted.
3. Zips whatever exists of the project folder into `attendance_tracker_<name>_archive.zip`.
4. Deletes the incomplete folder so nothing half-made is left behind.
5. Exits.

If you press it before the folder is created (like while typing the name), it says there's nothing to archive and exits.

The trap is removed right before the Python app starts, because it's only meant for the deploy part.

### What's in the zip

Only what was created before you pressed Ctrl+C. For example, if you press it when the script asks "Choose A or B", the zip has:

```
attendance_tracker_demo/
attendance_tracker_demo/attendance_checker.py
attendance_tracker_demo/Helpers/
attendance_tracker_demo/Helpers/config.json
attendance_tracker_demo/reports/
```

There's no `assets.csv` because the roster wasn't built yet. You can check with `unzip -l attendance_tracker_demo_archive.zip`.

### How to test it

1. Run `./deploy_agent.sh deploy` and type a name like `demo`.
2. When it asks "Choose A or B", press Ctrl+C.
3. Run `ls`. The folder `attendance_tracker_demo` should be gone and `attendance_tracker_demo_archive.zip` should be there.
4. Do the same with Ctrl+Z.

## How I tested it

- Deployed with option A and option B and checked `assets.csv` and `total_sessions` in `config.json` each time.
- Typed wrong inputs (empty name, letters instead of numbers, too many students) to make sure it asks again.
- Deployed the same name twice and tried both `y` and `n` for overwrite.
- Updated the thresholds and checked with `cat Helpers/config.json` that only those two numbers changed.
- Checked permissions with `ls -l`.
- Ran a marking session, archived, and checked the `archives/` folders. Also archived with no logs to make sure it didn't crash.
- Pressed Ctrl+C and Ctrl+Z at different points during the deploy.

## Video

Link to my walkthrough video: (paste your link here)