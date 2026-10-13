#!/bin/bash
# deploy_agent.sh - deploy, run and archive the attendance tracker
# usage: ./deploy_agent.sh  or  ./deploy_agent.sh deploy | run <name> | archive <name>

# folder the script is in
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES="$BASE_DIR/templates"

project_name=""
project_dir=""

# names for option B
names=("Alice Johnson" "Brian Okafor" "Chloe Martin" "Daniel Mensah" "Esther Uwase"
       "Felix Garcia" "Grace Kim" "Henry Brown" "Ines Nkurunziza" "Jamal Ali")


# ---- helpers ----

is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# sed -i.bak works on mac and linux, then delete the backup
edit_config() {
    sed -i.bak "$1" "$project_dir/Helpers/config.json"
    rm -f "$project_dir/Helpers/config.json.bak"
}

# delete the half made folder and stop
fail() {
    echo "Error: $1"
    if [ -n "$project_dir" ] && [ -d "$project_dir" ]; then
        rm -rf "$project_dir"
        echo "Removed the incomplete folder."
    fi
    exit 1
}


# ---- ctrl+c / ctrl+z ----

cleanup() {
    # ignore more presses while cleaning up
    trap '' INT TSTP

    echo ""
    echo "Deployment was interrupted ($1)!"

    if [ -n "$project_dir" ] && [ -d "$project_dir" ]; then
        folder=$(basename "$project_dir")
        echo "Saving what was created so far into ${folder}_archive.zip ..."
        cd "$BASE_DIR"
        rm -f "${folder}_archive.zip"
        zip -rq "${folder}_archive.zip" "$folder"
        rm -rf "$folder"
        echo "Archive created and the incomplete folder was deleted."
    else
        echo "The project folder wasn't created yet, so there's nothing to archive."
    fi

    echo "Exiting."
    exit 1
}


# ---- feature 1: deploy ----

deploy() {
    trap 'cleanup "Ctrl+C"' INT
    trap 'cleanup "Ctrl+Z"' TSTP

    echo "===== Deploying the Attendance Tracker ====="

    # check python3 and zip
    if ! command -v python3 > /dev/null 2>&1; then
        echo "Error: python3 is not installed. Install it and try again."
        exit 1
    fi
    echo "python3 is installed: $(python3 --version 2>&1)"

    if ! command -v zip > /dev/null 2>&1; then
        echo "Error: zip is not installed. Install it and try again."
        exit 1
    fi
    echo "zip is installed"

    for file in attendance_checker.py assets.csv config.json; do
        if [ ! -f "$TEMPLATES/$file" ]; then
            echo "Error: templates/$file is missing."
            exit 1
        fi
    done

    if [ ! -w "$BASE_DIR" ]; then
        echo "Error: no permission to create folders in $BASE_DIR"
        exit 1
    fi

    # get the project name
    echo ""
    while true; do
        read -p "Enter a name for the project: " project_name || exit 1
        if [[ "$project_name" =~ ^[A-Za-z0-9_-]+$ ]]; then
            break
        fi
        echo "Invalid name. Only letters, numbers, - and _ please (no spaces)."
    done

    target="$BASE_DIR/attendance_tracker_$project_name"

    if [ -d "$target" ]; then
        read -p "attendance_tracker_$project_name already exists. Overwrite it? (y/n): " answer || exit 1
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            rm -rf "$target" || { echo "Error: couldn't delete the old folder (permission denied?)"; exit 1; }
            echo "Old folder deleted."
        else
            echo "Not overwriting. Run the script again with a different name."
            exit 1
        fi
    fi

    # now the trap knows which folder to zip
    project_dir="$target"
    mkdir -p "$project_dir/Helpers" "$project_dir/reports" || fail "couldn't create the project folders"
    echo "Created attendance_tracker_$project_name/ with Helpers/ and reports/"

    # copy the files
    cp "$TEMPLATES/attendance_checker.py" "$project_dir/" || fail "couldn't copy attendance_checker.py"
    cp "$TEMPLATES/config.json" "$project_dir/Helpers/" || fail "couldn't copy config.json"
    echo "Copied attendance_checker.py and config.json from templates/"

    echo ""
    echo "How do you want to build Helpers/assets.csv?"
    echo "  A - copy students from the template"
    echo "  B - generate a new roster (counts start at 0)"
    while true; do
        read -p "Choose A or B: " option || exit 1
        case "$option" in
            A|a|B|b) break ;;
            *) echo "Please type A or B." ;;
        esac
    done

    if [ "$option" = "A" ] || [ "$option" = "a" ]; then
        max=$(tail -n +2 "$TEMPLATES/assets.csv" | grep -c .)
        while true; do
            read -p "How many students do you want to copy? (1-$max): " count || exit 1
            if is_number "$count" && [ "$count" -ge 1 ] && [ "$count" -le "$max" ]; then
                break
            fi
            echo "Please enter a number between 1 and $max."
        done
        count=$((10#$count))

        # header + the students
        head -n $((count + 1)) "$TEMPLATES/assets.csv" > "$project_dir/Helpers/assets.csv"

        # template already has 4 sessions so total stays 5
        echo "Copied $count students from the template (total_sessions stays 5)"
    else
        while true; do
            read -p "How many students do you want to generate? (1-50): " count || exit 1
            if is_number "$count" && [ "$count" -ge 1 ] && [ "$count" -le 50 ]; then
                break
            fi
            echo "Please enter a number between 1 and 50."
        done
        count=$((10#$count))

        echo "Email,Names,Attendance Count,Absence Count" > "$project_dir/Helpers/assets.csv"
        for ((i = 0; i < count; i++)); do
            if [ $i -lt ${#names[@]} ]; then
                name="${names[$i]}"
            else
                # no more names left
                name="Student $((i + 1))"
            fi
            # make the email from the name
            email="$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '.')@example.com"
            echo "$email,$name,0,0" >> "$project_dir/Helpers/assets.csv"
        done

        # new students so this is session 1
        edit_config 's/"total_sessions": *[0-9]*/"total_sessions": 1/'
        echo "Generated $count students (total_sessions set to 1)"
    fi

    # permissions
    chmod +x "$project_dir/attendance_checker.py" || fail "couldn't make attendance_checker.py executable"
    chmod 600 "$project_dir/Helpers/config.json" || fail "couldn't change permissions on config.json"
    echo ""
    echo "Permissions set:"
    echo "  attendance_checker.py -> executable (chmod +x)"
    echo "  Helpers/config.json   -> only the owner can read/write (chmod 600)"

    # thresholds
    echo ""
    read -p "Do you want to update the attendance alert thresholds? (y/n): " answer || exit 1
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        while true; do
            while true; do
                read -p "Warning threshold (press Enter for 75): " warning || exit 1
                [ -z "$warning" ] && warning=75
                if is_number "$warning" && [ "$warning" -le 100 ]; then break; fi
                echo "That's not a valid number. Enter a whole number from 0 to 100."
            done

            while true; do
                read -p "Failure threshold (press Enter for 50): " failure || exit 1
                [ -z "$failure" ] && failure=50
                if is_number "$failure" && [ "$failure" -le 100 ]; then break; fi
                echo "That's not a valid number. Enter a whole number from 0 to 100."
            done

            # remove leading zeros (08 -> 8)
            warning=$((10#$warning))
            failure=$((10#$failure))

            if [ "$warning" -gt "$failure" ]; then
                break
            fi
            echo "The warning threshold has to be higher than the failure threshold. Try again."
        done

        # change only the numbers
        edit_config "s/\"warning\": *[0-9]*/\"warning\": $warning/"
        edit_config "s/\"failure\": *[0-9]*/\"failure\": $failure/"
        chmod 600 "$project_dir/Helpers/config.json"
        echo "Thresholds updated: warning = $warning, failure = $failure"
    else
        echo "Keeping the default thresholds."
    fi

    # make sure everything is there
    for file in attendance_checker.py Helpers/assets.csv Helpers/config.json; do
        [ -f "$project_dir/$file" ] || fail "$file is missing after deploy"
    done
    [ -d "$project_dir/reports" ] || fail "reports/ is missing after deploy"

    # deploy done, remove the trap before running python
    trap - INT TSTP

    echo ""
    echo "Deployment finished! Starting the app to check that everything works..."
    run_app
}


# ---- pick a project (for run and archive) ----

choose_project() {
    project_name="$1"

    if [ -z "$project_name" ]; then
        echo "Deployed projects:"
        for dir in "$BASE_DIR"/attendance_tracker_*/; do
            [ -d "$dir" ] && echo "  $(basename "$dir" | sed 's/attendance_tracker_//')"
        done
        read -p "Which project? " project_name || exit 1
    fi

    # works with demo or attendance_tracker_demo
    project_name="${project_name%/}"
    project_name="${project_name#attendance_tracker_}"
    project_dir="$BASE_DIR/attendance_tracker_$project_name"

    if [ -z "$project_name" ] || [ ! -d "$project_dir" ]; then
        echo "Error: attendance_tracker_$project_name doesn't exist. Deploy it first."
        return 1
    fi
}


# ---- feature 2: run ----

run_app() {
    if [ ! -f "$project_dir/attendance_checker.py" ]; then
        echo "Error: attendance_checker.py not found in attendance_tracker_$project_name"
        return 1
    fi

    echo "------------------------------------------------"
    (cd "$project_dir" && python3 attendance_checker.py)
    echo "------------------------------------------------"
    echo "Session over. Logs are in attendance_tracker_$project_name/reports/"
}


# ---- feature 3: archive logs ----

archive_logs() {
    choose_project "$1" || return

    timestamp=$(date +%Y%m%d_%H%M%S)
    archived=0

    for log in attendance absent; do
        if [ -f "$project_dir/reports/$log.log" ]; then
            mkdir -p "$project_dir/archives/$log"
            mv "$project_dir/reports/$log.log" "$project_dir/archives/$log/${log}_$timestamp.log"
            echo "Archived $log.log -> attendance_tracker_$project_name/archives/$log/${log}_$timestamp.log"
            archived=$((archived + 1))
        else
            echo "No $log.log in reports/, skipping it."
        fi
    done

    if [ $archived -eq 0 ]; then
        echo "Nothing to archive. Run the app first."
    fi
}


# ---- menu / arguments ----

menu() {
    while true; do
        echo ""
        echo "===== Attendance Tracker - Deploy Agent ====="
        echo "1) Deploy the application"
        echo "2) Run the application"
        echo "3) Archive the logs"
        echo "4) Exit"
        read -p "Choose an option: " choice || exit 0

        case "$choice" in
            1) deploy ;;
            2) choose_project && run_app ;;
            3) archive_logs ;;
            4) echo "Bye!"; exit 0 ;;
            *) echo "Invalid option, choose 1-4." ;;
        esac
        project_dir=""
    done
}

case "$1" in
    "")      menu ;;
    deploy)  deploy ;;
    run)     choose_project "$2" && run_app ;;
    archive) archive_logs "$2" ;;
    *)
        echo "Unknown option: $1"
        echo "Usage: ./deploy_agent.sh [deploy | run <name> | archive <name>]"
        exit 1
        ;;
esac