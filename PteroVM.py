#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# --- Standard Library Imports ---
import os
import subprocess
import urllib.request
import urllib.error
import shutil
import tempfile
import sys
import traceback

# --- Configuration Constants ---
# Define the names of the scripts to be managed.
NOUR_SCRIPT_NAME = "nour.sh"
NOURD_SCRIPT_NAME = "nourd.sh"
# Define the authoritative URLs from which to download or update the scripts.
NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/main/nour.sh"
NOURD_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/main/nourd.sh"

# --- Helper Functions ---

def download_file(url_str: str, destination_path: str):
    """
    Downloads a file from a URL to a specified destination path safely and atomically.
    
    This function first downloads the content to a temporary file in the same
    directory. If the download is successful, it then atomically moves the
    temporary file to the final destination path. This prevents file corruption
    if the script is interrupted during the download.

    Args:
        url_str: The URL of the file to download.
        destination_path: The final path to save the file.

    Raises:
        IOError: If the download or file move operation fails.
    """
    # Ensure the destination directory exists.
    dest_dir = os.path.dirname(destination_path) or "."
    os.makedirs(dest_dir, exist_ok=True)

    temp_file_path = None  # Initialize to ensure it's available in the finally block.
    try:
        # Create a named temporary file. 'delete=False' is crucial because we need to
        # close it and then move it ourselves. It will not be deleted on close.
        with tempfile.NamedTemporaryFile(mode='wb', delete=False, dir=dest_dir,
                                         prefix=os.path.basename(destination_path) + "_",
                                         suffix=".tmpdownload") as temp_f:
            temp_file_path = temp_f.name
            # Open the remote URL and copy its content directly to our temp file.
            with urllib.request.urlopen(url_str) as response:
                shutil.copyfileobj(response, temp_f)
        
        # Once the download is complete, move the temp file to the final destination.
        # This operation is atomic on most systems, ensuring integrity.
        shutil.move(temp_file_path, destination_path)
    
    except Exception as e:
        # If any error occurs, attempt to clean up the temporary file.
        if temp_file_path and os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except OSError as oe:
                print(f"Warning: Failed to delete temporary file '{temp_file_path}' during error handling: {oe}")
        # Re-raise the exception as an IOError to be handled by the calling function.
        raise IOError(f"Failed to download or replace file '{os.path.basename(destination_path)}' from {url_str}: {e}") from e
    
    finally:
        # A final cleanup check. This ensures that even if an error occurred after
        # the temp file was created but before the 'except' block could clean it,
        # we still attempt to remove it.
        if temp_file_path and os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except OSError:
                print(f"Warning: Temporary file '{temp_file_path}' may still exist and could not be cleaned up.")


def set_executable_permission(file_path: str) -> bool:
    """
    Sets executable permission on the given file, similar to 'chmod +x'.

    This function first attempts to use the system's `chmod` command for consistency
    with system-level tools. If `chmod` is not found (e.g., on some minimal systems),
    it falls back to using Python's built-in `os.chmod` function.

    Args:
        file_path: The path to the file.

    Returns:
        True if the permission was set successfully, False otherwise.
    """
    abs_file_path = os.path.abspath(file_path)
    if not os.path.exists(abs_file_path):
        print(f"Cannot set permissions: File '{os.path.basename(file_path)}' does not exist at '{abs_file_path}'.")
        return False

    print(f"Setting executable permission on '{os.path.basename(file_path)}'...")
    try:
        # Primary method: Use the 'chmod' command for reliable behavior.
        process = subprocess.run(["chmod", "+x", abs_file_path],
                                 capture_output=True, text=True, check=False)
        if process.returncode != 0:
            print(f"Error setting permission (chmod exit code: {process.returncode}).")
            if process.stderr: print(f"chmod stderr: {process.stderr.strip()}")
            return False
        else:
            print(f"Executable permission set via 'chmod'.")
            return True
    except FileNotFoundError:
        # Fallback method: If 'chmod' isn't on the system PATH.
        print("Warning: 'chmod' command not found. Falling back to Python's os.chmod.")
        try:
            current_mode = os.stat(abs_file_path).st_mode
            # Add execute permissions for user, group, and others using a bitwise OR.
            # 0o111 is the octal representation of r-x r-x r-x.
            new_mode = current_mode | 0o111
            os.chmod(abs_file_path, new_mode)
            print(f"Successfully set executable permission using os.chmod.")
            return True
        except Exception as e_chmod:
            print(f"Fallback os.chmod also failed: {e_chmod}")
            return False
    except Exception as e:
        # Catch any other unexpected errors during the process.
        print(f"Unexpected error during permission setting: {e}")
        traceback.print_exc()
        return False


def download_and_set_permissions(script_url: str, script_name: str) -> str | None:
    """
    Orchestrates the download and permission-setting process for a script.

    Args:
        script_url: The URL to download the script from.
        script_name: The local filename to save the script as.

    Returns:
        The script's file path on full success, or None if any step fails.
    """
    print(f"Downloading '{script_name}' from {script_url}...")
    try:
        download_file(script_url, script_name)
        print(f"Download completed for '{script_name}'.")
    except (IOError, Exception) as e:
        print(f"Error downloading '{script_name}': {e}")
        return None

    # After a successful download, set the necessary permissions.
    if not set_executable_permission(script_name):
        print(f"Download of '{script_name}' succeeded but setting permissions failed.")
        return None
    
    print(f"Successfully downloaded and set permissions for '{script_name}'.")
    return script_name


def is_file_changed(local_path: str, remote_url: str) -> bool:
    """
    Compares local file content with content from a remote URL.

    Args:
        local_path: The path to the local file.
        remote_url: The URL pointing to the master version of the file.

    Returns:
        True if contents are different or if an error occurs (fail-safe).
        False if contents are identical.
    """
    print(f"Comparing local '{os.path.basename(local_path)}' with remote version...")
    try:
        # Fetch remote content.
        with urllib.request.urlopen(remote_url) as response:
            remote_content = response.read().decode('utf-8')
        
        # Read local content.
        with open(local_path, 'r', encoding='utf-8') as f_local:
            local_content = f_local.read()
            
        is_different = remote_content != local_content
        if is_different:
            print(f"Contents of '{os.path.basename(local_path)}' differ from remote.")
        else:
            print(f"Contents are the same.")
        return is_different
    except Exception as e:
        # On any error (network, file read, etc.), assume the file has changed.
        # This is a fail-safe approach to ensure the user gets a fresh copy.
        print(f"Error during comparison: {e}. Assuming file has changed.")
        return True


def run_script(script_path: str):
    """
    Executes the given shell script using the 'bash' interpreter.

    Args:
        script_path: The path of the script file to execute.
    """
    abs_script_path = os.path.abspath(script_path)
    # Safety checks before execution.
    if not os.path.exists(abs_script_path):
        print(f"Cannot run script: '{os.path.basename(script_path)}' does not exist.")
        return
    if not os.access(abs_script_path, os.X_OK):
        print(f"Cannot run script: '{os.path.basename(script_path)}' is not executable.")
        return

    print(f"Running '{os.path.basename(script_path)}'...")
    try:
        # Execute the script using a subprocess. The script's I/O will be
        # connected to the current console by default.
        process = subprocess.run(["bash", abs_script_path], check=False)
        print(f"'{os.path.basename(script_path)}' finished with exit code {process.returncode}.")
    except FileNotFoundError:
        print("Error: 'bash' command not found. Cannot run script.")
    except Exception as e:
        print(f"An error occurred while running script '{os.path.basename(script_path)}': {e}")
        traceback.print_exc()


def handle_download_choice_set_perms_and_run():
    """
    Prompts the user to choose a script to download if none are found locally.
    Then, it manages the download, permission setting, and execution of the chosen script.
    """
    print("Choose an option to download:")
    print(f"0: Download {NOUR_SCRIPT_NAME}")
    print(f"1: Download {NOURD_SCRIPT_NAME}")
    
    try:
        choice = input("Enter your choice (0 or 1): ").strip()
    except EOFError:
        print("\nNo input received. Exiting.")
        return

    # Determine which script to download based on user input.
    if choice == "0":
        script_url, script_name = NOUR_URL, NOUR_SCRIPT_NAME
    elif choice == "1":
        script_url, script_name = NOURD_URL, NOURD_SCRIPT_NAME
    else:
        print("Invalid choice. Exiting.")
        return

    # Orchestrate the process for the chosen script.
    downloaded_file = download_and_set_permissions(script_url, script_name)
    if downloaded_file:
        print(f"Preparing to run downloaded '{os.path.basename(downloaded_file)}'...")
        run_script(downloaded_file)
    else:
        print(f"Failed to process '{script_name}'. Script will not be run.")


def handle_script(script_name: str, script_url: str) -> bool:
    """
    Manages a single script: checks for existence, updates, sets permissions, and runs.

    This is the core logic for a script that already exists locally. It ensures the
    script is up-to-date and executable before running it.

    Args:
        script_name: The local name of the script file.
        script_url: The remote URL for update checks.

    Returns:
        True if the script was found locally and its lifecycle was handled.
        False if the script was not found locally.
    """
    if not os.path.exists(script_name):
        return False  # Let the main logic know the script wasn't found.
    
    print(f"Found '{script_name}'. Checking for updates...")
    file_to_execute = script_name

    # Check if a new version of the script is available.
    if is_file_changed(script_name, script_url):
        print(f"'{script_name}' has changed. Attempting to download new version...")
        updated_file = download_and_set_permissions(script_url, script_name)
        if updated_file:
            print(f"Successfully updated '{script_name}'.")
            file_to_execute = updated_file
        else:
            # If the update fails, we will fall back to using the old version.
            print(f"Failed to update '{script_name}'. Attempting to run existing version.")
    else:
        print(f"'{script_name}' is up to date.")

    # At this point, we have a file to execute (either the updated or old one).
    # Now, ensure it's runnable.
    is_executable = os.access(file_to_execute, os.X_OK)
    can_run = False

    if is_executable:
        print(f"'{os.path.basename(file_to_execute)}' is already executable.")
        can_run = True
    else:
        # If the file is not executable, we must try to set permissions.
        print(f"Warning: '{os.path.basename(file_to_execute)}' is NOT executable. Attempting to set permissions...")
        if set_executable_permission(file_to_execute):
            can_run = True
        else:
            print(f"Failed to set executable permission. The script will not be run.")

    # Final step: run the script if it's ready.
    if can_run:
        print(f"Preparing to run '{os.path.basename(file_to_execute)}'...")
        run_script(file_to_execute)
    
    return True # Return true because the script was found and handled.


# --- Main Execution Block ---
def main():
    """
    Main entry point for the script launcher.
    
    The logic is as follows:
    1. Check for `nour.sh`. If it exists, handle it (update/run) and exit.
    2. If not, check for `nourd.sh`. If it exists, handle it and exit.
    3. If neither exists locally, prompt the user to download one.
    """
    try:
        # First, try to find and handle the primary script.
        if handle_script(NOUR_SCRIPT_NAME, NOUR_URL):
            return

        # If the primary script was not found, try the secondary script.
        if handle_script(NOURD_SCRIPT_NAME, NOURD_URL):
            return

        # If neither script was found, prompt the user for a choice.
        print(f"Neither '{NOUR_SCRIPT_NAME}' nor '{NOURD_SCRIPT_NAME}' found locally.")
        handle_download_choice_set_perms_and_run()

    except KeyboardInterrupt:
        # Cleanly handle Ctrl+C from the user.
        print("\nOperation interrupted by user. Exiting.")
        sys.exit(130)
    except Exception as e:
        # Catch any other unexpected errors for graceful exit and debugging.
        print(f"An unexpected error occurred in main: {e}")
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    # This prevents the main() function from running if the script is imported
    # as a module into another script.
    main()
