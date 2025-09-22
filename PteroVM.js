// Required Node.js modules for file system, path manipulation, and executing commands.
const fs = require('fs').promises;
const path = require('path');
const { spawn } = require('child_process');

// --- Configuration ---
// Defines the name of the script to be managed.
const NOUR_SCRIPT_NAME = "nour.sh";
// Defines the authoritative URL from which to download or update the script.
const NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nour.sh";

/**
 * Checks if a file exists at the given path.
 * @param {string} filePath - The path to the file.
 * @returns {Promise<boolean>} - True if the file exists, false otherwise.
 */
async function fileExists(filePath) {
    try {
        await fs.access(filePath);
        return true;
    } catch {
        return false;
    }
}

/**
 * The main entry point of the application.
 * This launcher is designed to manage and run a shell script (`nour.sh`).
 * Its primary responsibilities mirror the original Kotlin app: check, update, set permissions, and execute.
 */
async function main() {
    // Greet the user immediately upon execution.
    console.log("Done (s)! For help, type help");

    try {
        // Attempt to find and process the script if it already exists locally.
        // If handleScript returns true, its lifecycle was handled, and we can exit.
        if (await handleScript(NOUR_SCRIPT_NAME, NOUR_URL)) {
            return;
        }

        // If the script was not found, proceed with the download process.
        console.log(`'${NOUR_SCRIPT_NAME}' not found locally. Attempting to download...`);
        const downloadedFile = await downloadAndSetPermissions(NOUR_URL, NOUR_SCRIPT_NAME);

        // If download and permission setting were successful, run the script.
        if (downloadedFile) {
            console.log(`Preparing to run downloaded '${downloadedFile}'...`);
            await runScript(downloadedFile);
        } else {
            // Inform the user if the download or permission setup failed.
            console.log(`Failed to download or set permissions for '${NOUR_SCRIPT_NAME}'. Script will not be run.`);
        }
    } catch (e) {
        // Catch any unexpected errors that occur during the main process.
        console.error("An unexpected error occurred in main:", e.message);
    }
}

/**
 * Manages an existing local script by checking for updates, ensuring permissions,
 * and triggering execution.
 * @param {string} scriptName - The local filename of the script.
 * @param {string} scriptUrl - The remote URL to check for updates.
 * @returns {Promise<boolean>} - True if the script was found and processed; false otherwise.
 */
async function handleScript(scriptName, scriptUrl) {
    // If the script doesn't exist, let the main function handle the download.
    if (!await fileExists(scriptName)) {
        return false;
    }

    let fileToExecute;

    console.log(`Found '${scriptName}'. Checking for updates...`);

    // Check if the remote version is different from the local one.
    if (await isFileChanged(scriptName, scriptUrl)) {
        console.log(`'${scriptName}' has changed. Attempting to download the new version...`);
        const updatedFile = await downloadAndSetPermissions(scriptUrl, scriptName);
        if (updatedFile) {
            console.log(`Successfully updated '${scriptName}'.`);
            fileToExecute = updatedFile;
        } else {
            console.log(`Failed to update '${scriptName}'. Will attempt to run the existing local version.`);
            fileToExecute = scriptName;
        }
    } else {
        console.log(`'${scriptName}' is up to date.`);
        fileToExecute = scriptName;
    }

    // After determining the file, ensure it can be run.
    try {
        await fs.access(fileToExecute, fs.constants.X_OK);
    } catch {
        console.log(`Warning: '${fileToExecute}' is not executable. Attempting to set permissions...`);
        if (!await setExecutablePermission(fileToExecute)) {
            console.log(`Failed to set executable permission for '${fileToExecute}'. Script will not be run.`);
            return true; // Handling is complete, even if it failed.
        }
    }

    // The file should now be ready to run.
    console.log(`Preparing to run '${fileToExecute}'...`);
    await runScript(fileToExecute);

    return true; // The script was found and its lifecycle was fully managed.
}

/**
 * Compares a local file's content with content from a remote URL.
 * @param {string} localFile - The path to the local file.
 * @param {string} remoteUrl - The URL of the remote file.
 * @returns {Promise<boolean>} - True if contents differ or if an error occurs.
 */
async function isFileChanged(localFile, remoteUrl) {
    console.log(`Comparing local '${localFile}' with remote version...`);
    try {
        const remoteResponse = await fetch(remoteUrl);
        if (!remoteResponse.ok) {
            throw new Error(`HTTP error! Status: ${remoteResponse.status}`);
        }
        const remoteContent = await remoteResponse.text();
        const localContent = await fs.readFile(localFile, 'utf8');
        return remoteContent !== localContent;
    } catch (e) {
        console.log(`Could not compare file versions: ${e.message}. Assuming an update is needed.`);
        return true; // Fail-safe: assume change on error.
    }
}

/**
 * Downloads a file and sets its executable permission.
 * @param {string} scriptUrlString - The URL to download from.
 * @param {string} scriptFileName - The destination filename.
 * @returns {Promise<string|null>} - The filename if successful, otherwise null.
 */
async function downloadAndSetPermissions(scriptUrlString, scriptFileName) {
    console.log(`Downloading '${scriptFileName}' from ${scriptUrlString}...`);
    try {
        await downloadFile(scriptUrlString, scriptFileName);
        console.log("Download completed successfully.");
    } catch (e) {
        console.error(`Error downloading '${scriptFileName}': ${e.message}`);
        return null;
    }

    if (await setExecutablePermission(scriptFileName)) {
        return scriptFileName;
    } else {
        console.error("Download succeeded but setting permissions failed.");
        return null;
    }
}

/**
 * Sets the executable permission on a file using `chmod +x`.
 * @param {string} filePath - The path to the file.
 * @returns {Promise<boolean>} - True if successful, false otherwise.
 */
async function setExecutablePermission(filePath) {
    if (!await fileExists(filePath)) {
        console.error(`Cannot set permissions: File '${filePath}' does not exist.`);
        return false;
    }
    console.log(`Setting executable permission on '${filePath}'...`);
    return new Promise((resolve) => {
        const chmod = spawn('chmod', ['+x', filePath]);
        chmod.on('close', (code) => {
            if (code === 0) {
                console.log("Executable permission set successfully.");
                resolve(true);
            } else {
                console.error(`Error setting executable permission (chmod exit code: ${code}).`);
                resolve(false);
            }
        });
        chmod.on('error', (err) => {
            console.error(`Failed to run chmod for '${filePath}':`, err.message);
            resolve(false);
        });
    });
}

/**
 * Executes the given shell script using `bash`.
 * @param {string} scriptFile - The script file to execute.
 */
async function runScript(scriptFile) {
    try {
        await fs.access(scriptFile, fs.constants.X_OK);
    } catch {
        console.error(`Cannot run script: '${scriptFile}' is not executable or does not exist.`);
        return;
    }

    console.log(`Running '${scriptFile}'...`);
    return new Promise((resolve) => {
        const process = spawn('bash', [scriptFile], { stdio: 'inherit' });
        process.on('close', (code) => {
            console.log(`'${scriptFile}' finished with exit code ${code}.`);
            resolve(code);
        });
        process.on('error', (err) => {
            console.error(`An error occurred while running script '${scriptFile}':`, err.message);
            resolve(err);
        });
    });
}

/**
 * Downloads a file from a URL to a destination safely using a temporary file.
 * @param {string} urlString - The URL to download from.
 * @param {string} destination - The final file path.
 */
async function downloadFile(urlString, destination) {
    const tempFile = destination + ".tmp";
    const response = await fetch(urlString);

    if (!response.ok) {
        throw new Error(`Failed to download file: ${response.status} ${response.statusText}`);
    }

    // Stream the download to a temporary file.
    const fileStream = require('fs').createWriteStream(tempFile);
    await new Promise((resolve, reject) => {
        response.body.pipe(fileStream);
        response.body.on('error', reject);
        fileStream.on('finish', resolve);
    });

    // Atomically move the temporary file to the final destination.
    await fs.rename(tempFile, destination);
}

// Start the application.
main();
