#!/bin/sh

# Usage: ./download_changesets.sh -u USERNAME [-s SINCE_DATE] [-o OUTPUT_DIR] [-l LOG_FILE] [-d]

# Description: This script downloads all changesets of an OpenStreetMap user
# since a given date. To get all, set SINCE_DATE to before their signup. The
# API currently lists at most 100 changesets at a time, which is why we loop.

# No user servicable parts below. This will create a directory called:
# user_SINCE_DATE
# which will contain tons of files called c1234.osc (one for each changeset)

# Variables

user=
since=2013-11-01T00:00:00
end_date=
output_dir=
current_time=
has_more_changesets=1
logfile=/dev/stdout
dry_run=false


# Parse command-line arguments
while getopts ":u:s:o:l:d" opt; do
  case $opt in
    u) user="$OPTARG";;
    s) since="$OPTARG";;
    o) output_dir="$OPTARG";;
    l) logfile="$OPTARG";;
    d) dry_run=true;;
    *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
  esac
done

# Check if the username is provided
if [ -z "$user" ]; then
    printf "Error: Username is required.\n"
    exit 1
fi

# Set the default output directory if not provided
if [ -z "$output_dir" ]; then
    output_dir="${user}_${since}"
fi

# Create output directory if it doesn't exist
if [ ! -d "$output_dir" ]; then
    mkdir "$output_dir"
fi

# Initialize current_time variable
current_time=$(date -u +%Y-%m-%dT%H:%M:%S)

# Function to download changesets
download_changesets() {
    # Create a temporary file
    temp_file=$(mktemp -t "download-changesets-$user-XXXXXX")

    while [ $has_more_changesets -eq 1 ]; do
        # Fetch the list of changesets
        curl -s -o "$temp_file" "https://api.openstreetmap.org/api/0.6/changesets?display_name=$user&time=$since,$current_time"

        # Update the current_time for the next API call
        current_time=$(grep "<changeset" "$temp_file" | tail -1 | cut -d\" -f4)
        current_time=$(date +"%Y-%m-%dT%H:%M:%SZ" -u -d "$current_time + 1 second")

        # Break the loop if the end_date is reached
        if [ -n "$end_date" ] && [ "$(date -d "$current_time" +%s)" -gt "$(date -d "$end_date" +%s)" ]; then
            break
        fi

        # Set has_more_changesets to 0, assuming no more changesets are available
        has_more_changesets=0

        # Process each changeset ID
        grep "<changeset" "$temp_file" | cut -d\" -f2 | while read -r id; do
            # Check if the changeset file already exists
            if [ -f "$output_dir/changeset_$id.osc" ]; then
                :
            else
                if [ "$dry_run" = true ]; then
                    printf "Dry run: Changeset $id would be downloaded.\n" >> "$logfile"
                else
                    # Download the changeset with retries and logging
                    attempt=0
                    max_attempts=3
                    while [ $attempt -lt $max_attempts ]; do
                        printf "Downloading changeset $id (attempt $(($attempt + 1)) of $max_attempts)...\n" >> "$logfile"
                        if curl -s -o "$output_dir/changeset_$id.osc" "https://api.openstreetmap.org/api/0.6/changeset/$id/download"; then
                            printf "Changeset $id downloaded successfully.\n" >> "$logfile"
                            break
                        else
                            printf "Failed to download changeset $id. Retrying...\n" >> "$logfile"
                            sleep $((2 ** $attempt))
                            attempt=$((attempt + 1))
                        fi
                    done
                    
                    # Set has_more_changesets to 1, indicating that more changesets are available
                    has_more_changesets=1
                fi
            fi
        done
    done

    # Remove the temporary file
    rm -f "$temp_file"
}

# Call the download_changesets function
download_changesets

# Print summary report
total_changesets=$(find "$output_dir" -name "changeset_*.osc" | wc -l)
total_size=$(du -sh "$output_dir" | cut -f1)
printf "Summary:\nTotal Changesets: %s\nTotal Size: %s\n" "$total_changesets" "$total_size" >> "$logfile"

# Display help message
if [ $# -eq 0 ]; then
    printf "Usage: ./script.sh -u USERNAME [-s SINCE_DATE] [-e END_DATE] [-o OUTPUT_DIR] [-l LOG_FILE] [-d]\n"
    printf "Options:\n"
    printf "  -u    Specify the OpenStreetMap username.\n"
    printf "  -s    Specify the start date for downloading changesets (default: 2013-11-01T00:00:00).\n"
    printf "  -o    Specify the output directory (default: USERNAME_SINCE_DATE).\n"
    printf "  -l    Specify the log file location (default: stdout).\n"
    printf "  -d    Enable dry-run mode, which lists changesets without downloading them.\n"
    exit 1
fi
