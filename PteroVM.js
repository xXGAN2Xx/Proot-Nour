const fs = require('fs').promises;
const { createWriteStream, existsSync } = require('fs');
const https = require('https');
const { spawn } = require('child_process');
const path = require('path');
const readline = require('readline');

// --- Constants ---
const NOUR_SCRIPT_NAME = "nour.sh";
const NOURD_SCRIPT_NAME = "nourd.sh";
const NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/main/nour.sh";
const NOURD_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/main/nourd.sh";

/**
 * Main entry point of the script.
 */
async function main() {
    try {
        // Attempt to handle the primary script. If found and processed, exit.
        if (await handleScript(NOUR_SCRIPT_NAME, NOUR_URL)) {
            return;
        }

        // Attempt to handle the secondary script. If found and processed, exit.
        if (await handleScript(NOURD_SCRIPT_NAME, NOURD_URL)) {
            return;
        }

        // If neither script exists locally, prompt the user to download one.
        console.log(`Neither '${NOUR_SCRIPT_NAME}' nor '${NOURD_SCRIPT_NAME}' found locally. Please choose a script to download.`);
        await handleDownloadChoiceSetPermsAndRun();

    } catch (e) {
        console.error(`An unexpected error occurred in main: ${e.message}`);
        console.error(e.stack);
    }
}

/**
 * Checks for a script, updates it if necessary, sets permissions, and runs it.
 * @param {string} scriptName - The local name of the script file.
 * @param {string} scriptUrl - The remote URL to check for updates and download from.
 * @returns {Promise<boolean>} - True if the script was found and processed, false otherwise.
 */
async function handleScript(scriptName, scriptUrl) {
    if (!existsSync(scriptName)) {
        return false; // Script does not exist locally, so we can't handle it.
    }

    let fileToExecute = scriptName;
    let canRun = false;

    console.log(`Found '${scriptName}'. Checking for updates...`);
    const hasChanged = await isFileChanged(scriptName, scriptUrl);

    if (hasChanged) {
        console.log(`'${scriptName}' has changed or an error occurred. Attempting to download the new version...`);
        const updatedFile = await downloadAndSetPermissions(scriptUrl, scriptName);
        if (updatedFile) {
            console.log(`Successfully updated '${scriptName}'.`);
            fileToExecute = updatedFile;
            // Permissions were set by the download function, so it should be runnable.
            canRun = await checkExecutable(fileToExecute);
            if (!canRun) {
                 console.error(`Error: Updated file '${fileToExecute}' is not executable despite a successful update.`);
            }
        } else {
            console.log(`Failed to update '${scriptName}'. Attempting to run the existing local version.`);
            // Fallback to existing file, try to set permissions and run.
            if (await setExecutablePermission(fileToExecute)) {
                canRun = await checkExecutable(fileToExecute);
            }
        }
    } else {
        console.log(`'${scriptName}' is up to date.`);
        // File is up-to-date, check if it's already executable.
        if (await checkExecutable(fileToExecute)) {
            console.log(`'${fileToExecute}' is already executable. Skipping permission setting.`);
            canRun = true;
        } else {
            console.warn(`Warning: Up-to-date file '${fileToExecute}' is NOT executable. Attempting to set permissions...`);
            if (await setExecutablePermission(fileToExecute)) {
                canRun = await checkExecutable(fileToExecute);
            }
        }
    }

    if (canRun) {
        console.log(`Preparing to run '${fileToExecute}'...`);
        await runScript(fileToExecute);
    } else {
        console.error(`Script '${fileToExecute}' will not be run due to permission issues.`);
    }
    
    return true; // Return true because the script was found and processed.
}

/**
 * Compares local file content with remote URL content.
 * @param {string} localFile - Path to the local file.
 * @param {string} remoteUrl - URL of the remote file.
 * @returns {Promise<boolean>} - True if contents differ or an error occurs.
 */
async function isFileChanged(localFile, remoteUrl) {
    try {
        const [remoteContent, localContent] = await Promise.all([
            fetchUrl(remoteUrl),
            fs.readFile(localFile, 'utf-8')
        ]);
        const changed = remoteContent !== localContent;
        console.log(`Contents for '${localFile}' are ${changed ? 'different' : 'the same'}.`);
        return changed;
    } catch (e) {
        console.warn(`Error during file comparison for '${localFile}': ${e.message}. Assuming it has changed.`);
        return true;
    }
}

/**
 * Downloads a script, and then sets its permissions to be executable.
 * @param {string} scriptUrlString - The URL to download from.
 * @param {string} scriptFileName - The destination file name.
 * @returns {Promise<string|null>} - The file path on success, or null on failure.
 */
async function downloadAndSetPermissions(scriptUrlString, scriptFileName) {
    console.log(`Downloading '${scriptFileName}' from ${scriptUrlString}...`);
    try {
        await downloadFile(scriptUrlString, scriptFileName);
        console.log(`Download completed for '${scriptFileName}'.`);
    } catch (e) {
        console.error(`Error downloading '${scriptFileName}': ${e.message}`);
        return null;
    }

    if (!await setExecutablePermission(scriptFileName)) {
        console.error(`Download of '${scriptFileName}' succeeded, but setting permissions failed.`);
        return null;
    }
    
    console.log(`Successfully downloaded and set permissions for '${scriptFileName}'.`);
    return scriptFileName;
}

/**
 * Prompts the user to choose a script to download, then downloads and runs it.
 */
async function handleDownloadChoiceSetPermsAndRun() {
    console.log("Choose an option to download:");
    console.log(`0: Download ${NOUR_SCRIPT_NAME}`);
    console.log(`1: Download ${NOURD_SCRIPT_NAME}`);
    const choice = await askQuestion("Enter your choice (0 or 1): ");

    const options = {
        "0": { url: NOUR_URL, name: NOUR_SCRIPT_NAME },
        "1": { url: NOURD_URL, name: NOURD_SCRIPT_NAME }
    };

    const selection = options[choice.trim()];
    if (!selection) {
        console.log("Invalid choice. Exiting.");
        return;
    }

    const downloadedFile = await downloadAndSetPermissions(selection.url, selection.name);
    if (downloadedFile) {
        console.log(`Preparing to run downloaded '${downloadedFile}'...`);
        await runScript(downloadedFile);
    } else {
        console.error(`Failed to download or set permissions for '${selection.name}'. Script will not be run.`);
    }
}

// --- Helper Functions ---

/**
 * Downloads a file atomically (downloads to temp file, then renames).
 * @param {string} urlString - The URL of the file to download.
 * @param {string} destination - The final path for the downloaded file.
 */
async function downloadFile(urlString, destination) {
    const tempFilePath = path.join(path.dirname(destination), `.${path.basename(destination)}.tmpdownload`);
    if (existsSync(tempFilePath)) await fs.unlink(tempFilePath);

    const fileStream = createWriteStream(tempFilePath);

    return new Promise((resolve, reject) => {
        const request = https.get(urlString, (response) => {
            if (response.statusCode < 200 || response.statusCode >= 300) {
                fileStream.close(() => fs.unlink(tempFilePath).catch(()=>{}));
                return reject(new Error(`Request failed with status code ${response.statusCode}`));
            }
            response.pipe(fileStream);
        });

        fileStream.on('finish', () => {
            fileStream.close(async () => {
                try {
                    await fs.rename(tempFilePath, destination);
                    resolve();
                } catch (err) {
                    reject(err);
                }
            });
        });

        request.on('error', (err) => {
            fileStream.close(() => fs.unlink(tempFilePath).catch(()=>{}));
            reject(err);
        });
    });
}

/**
 * Runs a shell script and waits for it to complete.
 * @param {string} scriptPath - The path to the script to execute.
 */
function runScript(scriptPath) {
    return new Promise((resolve, reject) => {
        console.log(`Running 'bash ./${scriptPath}'...`);
        const process = spawn('bash', [`./${scriptPath}`], { stdio: 'inherit' });

        process.on('close', (code) => {
            console.log(`'${scriptPath}' finished with exit code ${code}.`);
            code === 0 ? resolve() : reject(new Error(`Script exited with code ${code}`));
        });
        process.on('error', reject);
    });
}

/**
 * Sets the executable permission (+x) on a file using chmod.
 * @param {string} filePath - The path to the file.
 * @returns {Promise<boolean>} - True on success, false on failure.
 */
function setExecutablePermission(filePath) {
    return new Promise((resolve) => {
        console.log(`Setting executable permission on '${filePath}'...`);
        const chmod = spawn('chmod', ['+x', filePath]);
        chmod.on('close', (code) => {
            if (code === 0) {
                console.log(`Executable permission set for '${filePath}'.`);
                resolve(true);
            } else {
                console.error(`chmod process for '${filePath}' exited with code ${code}.`);
                resolve(false);
            }
        });
        chmod.on('error', (err) => {
            console.error(`Failed to start chmod for '${filePath}': ${err.message}`);
            resolve(false);
        });
    });
}

/**
 * Checks if a file is executable.
 * @param {string} filePath - The path to the file.
 * @returns {Promise<boolean>} - True if the file is executable.
 */
async function checkExecutable(filePath) {
    try {
        await fs.access(filePath, fs.constants.X_OK);
        return true;
    } catch {
        return false;
    }
}

/**
 * Fetches content from a URL.
 * @param {string} urlString - The URL to fetch.
 * @returns {Promise<string>} - The content of the URL.
 */
function fetchUrl(urlString) {
    return new Promise((resolve, reject) => {
        https.get(urlString, (res) => {
            if (res.statusCode < 200 || res.statusCode >= 300) {
                return reject(new Error(`HTTP request failed: ${res.statusCode}`));
            }
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () => resolve(data));
        }).on('error', reject);
    });
}

/**
 * Prompts the user with a question and returns their input.
 * @param {string} query - The question to ask the user.
 * @returns {Promise<string>} - The user's answer.
 */
function askQuestion(query) {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
    });
    return new Promise(resolve => rl.question(query, ans => {
        rl.close();
        resolve(ans);
    }));
}

// --- Start Execution ---
main();
