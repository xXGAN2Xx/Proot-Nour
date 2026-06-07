const fs = require("fs");
const fsPromises = require("fs/promises");
const path = require("path");
const https = require("https");
const http = require("http");
const { execFile, execSync, spawn } = require("child_process");
const { promisify } = require("util");
const stream = require("stream");
const pipeline = promisify(stream.pipeline);

const NOUR_SCRIPT_NAME = "nour.sh";
const NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nour.sh";

async function main() {
    console.log("Done (s)! For help, type help");

    try {
        if (await handleScript(NOUR_SCRIPT_NAME, NOUR_URL)) {
            return;
        }

        console.log(`'${NOUR_SCRIPT_NAME}' not found locally. Attempting to download...`);
        const downloadedFile = await downloadAndSetPermissions(NOUR_URL, NOUR_SCRIPT_NAME);
        if (downloadedFile !== null) {
            console.log(`Preparing to run downloaded '${downloadedFile}'...`);
            await runScript(downloadedFile);
        } else {
            console.log(`Failed to download or set permissions for '${NOUR_SCRIPT_NAME}'. Script will not be run.`);
        }

    } catch (e) {
        console.log(`An unexpected error occurred in main: ${e.message}`);
        console.error(e);
    }
}

async function handleScript(scriptName, scriptUrl) {
    let fileToExecute;
    let wasSuccessfullyUpdated;
    let isUpToDateAndSkippingPermSet;

    if (fs.existsSync(scriptName)) {
        console.log(`Found '${scriptName}'. Checking for updates...`);
        if (await isFileChanged(scriptName, scriptUrl)) {
            console.log(`'${scriptName}' has changed or an error occurred during check. Attempting to download the new version...`);
            const updatedFile = await downloadAndSetPermissions(scriptUrl, scriptName);
            if (updatedFile !== null) {
                fileToExecute = updatedFile;
                wasSuccessfullyUpdated = true;
                isUpToDateAndSkippingPermSet = false;
                console.log(`Successfully updated '${scriptName}'.`);
            } else {
                console.log(`Failed to update '${scriptName}'. Will attempt to run the existing local version '${scriptName}'.`);
                fileToExecute = scriptName;
                wasSuccessfullyUpdated = false;
                isUpToDateAndSkippingPermSet = false;
            }
        } else {
            console.log(`'${scriptName}' is up to date.`);
            fileToExecute = scriptName;
            wasSuccessfullyUpdated = false;
            isUpToDateAndSkippingPermSet = true;
        }
    } else {
        return false;
    }

    let canRun = false;

    if (wasSuccessfullyUpdated) {
        if (isExecutable(fileToExecute)) {
            console.log(`Permissions for updated '${fileToExecute}' were set during download.`);
            canRun = true;
        } else {
            console.log(`Error: Updated file '${fileToExecute}' is not executable despite successful update and permissioning process. Cannot run.`);
        }
    } else if (isUpToDateAndSkippingPermSet) {
        console.log(`Skipping explicit permission setting for up-to-date file '${fileToExecute}'.`);
        if (isExecutable(fileToExecute)) {
            console.log(`'${fileToExecute}' is already executable.`);
            canRun = true;
        } else {
            console.log(`Warning: Up-to-date file '${fileToExecute}' is NOT executable. Permission setting was skipped as requested. Script will not be run.`);
            canRun = false;
        }
    } else {
        console.log(`Attempting to set/verify permissions for '${fileToExecute}' (e.g., fallback or initial run scenario)...`);
        if (await setExecutablePermission(fileToExecute)) {
            if (isExecutable(fileToExecute)) {
                console.log(`Permissions set successfully for '${fileToExecute}'.`);
                canRun = true;
            } else {
                console.log(`Error: Setting permissions for '${fileToExecute}' was reported as successful, but the file is still not executable. Cannot run.`);
            }
        } else {
            console.log(`Failed to set executable permission for '${fileToExecute}'. Script will not be run.`);
        }
    }

    if (canRun) {
        console.log(`Preparing to run '${fileToExecute}'...`);
        await runScript(fileToExecute);
    } else {
        console.log(`Script '${fileToExecute}' will not be run due to permission issues or because it was not made executable.`);
    }
    return true;
}

async function isFileChanged(localFile, remoteUrl) {
    console.log(`Comparing local '${localFile}' with remote '${remoteUrl}'...`);
    try {
        const remoteContent = await fetchText(remoteUrl);
        const localContent = await fsPromises.readFile(localFile, "utf-8");
        const changed = remoteContent !== localContent;
        if (changed) {
            console.log(`Contents differ for '${localFile}'.`);
        } else {
            console.log(`Contents are the same for '${localFile}'.`);
        }
        return changed;
    } catch (e) {
        if (e.code === "ENOENT" || e.code === "EACCES" || e.code === "ERR_NETWORK") {
            console.log(`IO error during comparison for '${localFile}': ${e.message}. Assuming it has changed to be safe.`);
        } else {
            console.log(`Unexpected error comparing file '${localFile}' with remote: ${e.message}. Assuming it has changed.`);
            console.error(e);
        }
        return true;
    }
}

async function downloadAndSetPermissions(scriptUrlString, scriptFileName) {
    let url;
    try {
        url = new URL(scriptUrlString);
    } catch (e) {
        console.log(`Error: Invalid URL format: ${scriptUrlString}`);
        return null;
    }

    console.log(`Downloading '${scriptFileName}' from ${scriptUrlString}...`);
    try {
        await downloadFile(url, scriptFileName);
        console.log(`Download completed for '${scriptFileName}'.`);
    } catch (e) {
        console.log(`Error downloading '${scriptFileName}': ${e.message}`);
        console.error(e);
        return null;
    }

    if (!(await setExecutablePermission(scriptFileName))) {
        console.log(`Download of '${scriptFileName}' succeeded but setting permissions failed.`);
        return null;
    }
    console.log(`Successfully downloaded and ensured permissions for '${scriptFileName}'.`);
    return scriptFileName;
}

async function setExecutablePermission(file) {
    if (!fs.existsSync(file)) {
        console.log(`Cannot set permissions: File '${file}' does not exist at path '${path.resolve(file)}'.`);
        return false;
    }
    console.log(`Setting executable permission on '${file}'...`);
    try {
        const absolutePath = path.resolve(file);
        const result = await execFileAsync("chmod", ["+x", absolutePath]);

        if (result.code !== 0) {
            const errorOutput = result.stderr.trim();
            const stdOutput = result.stdout.trim();
            console.log(`Error setting executable permission for '${file}' (chmod exit code: ${result.code}).`);
            if (errorOutput.length > 0) console.log(`chmod stderr: ${errorOutput}`);
            if (stdOutput.length > 0) console.log(`chmod stdout: ${stdOutput}`);
            return false;
        } else {
            console.log(`Executable permission set for '${file}'.`);
            return true;
        }
    } catch (e) {
        console.log(`Error while trying to run chmod for '${file}': ${e.message}`);
        console.error(e);
        return false;
    }
}

async function runScript(scriptFile) {
    if (!fs.existsSync(scriptFile)) {
        console.log(`Cannot run script: '${scriptFile}' does not exist at ${path.resolve(scriptFile)}.`);
        return;
    }
    if (!isExecutable(scriptFile)) {
        console.log(`Cannot run script: '${scriptFile}' is not executable. Path: ${path.resolve(scriptFile)}`);
        return;
    }

    console.log(`Running '${scriptFile}' and waiting for it to complete...`);
    try {
        const absolutePath = path.resolve(scriptFile);
        const exitCode = await new Promise((resolve, reject) => {
            const child = spawn("bash", [absolutePath], { stdio: "inherit" });
            child.on("close", (code) => resolve(code));
            child.on("error", (err) => reject(err));
        });
        console.log(`'${scriptFile}' finished with exit code ${exitCode}.`);

        if (exitCode === 0) {
            console.log("Script completed successfully. Exiting program...");
            process.exit(0);
        }
    } catch (e) {
        console.log(`Error while trying to run script '${scriptFile}': ${e.message}`);
        console.error(e);
    }
}

async function downloadFile(url, destination) {
    const dir = path.dirname(path.resolve(destination));
    const tmpFileName = `${path.basename(destination)}.tmpdownload-${Date.now()}`;
    const tempFilePath = path.join(dir, tmpFileName);

    try {
        const response = await fetchUrl(url);

        if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
            // Follow redirect
            return downloadFile(new URL(response.headers.location, url.href), destination);
        }

        if (response.statusCode !== 200) {
            throw new Error(`HTTP ${response.statusCode}`);
        }

        const writeStream = fs.createWriteStream(tempFilePath);
        await pipeline(response, writeStream);

        // Atomic move: rename to final destination
        await fsPromises.rename(tempFilePath, path.resolve(destination));
    } catch (e) {
        try {
            if (fs.existsSync(tempFilePath)) {
                await fsPromises.unlink(tempFilePath);
            }
        } catch (cleanupErr) {
            console.log(`Warning: Failed to delete temporary file: ${tempFilePath}`);
        }
        throw new Error(`Failed to download or replace file '${destination}' from ${url.href}: ${e.message}`);
    } finally {
        try {
            if (fs.existsSync(tempFilePath)) {
                const tmpStat = await fsPromises.stat(tempFilePath).catch(() => null);
                const destPath = path.resolve(destination);
                const destStat = await fsPromises.stat(destPath).catch(() => null);

                if (tmpStat && tmpStat.size > 0 && !destStat) {
                    await fsPromises.unlink(tempFilePath).catch(() => {
                        console.log(`Warning: Temporary file ${tempFilePath} could not be deleted after failed operation.`);
                    });
                } else if (tmpStat && (!destStat || destStat.size !== tmpStat.size)) {
                    await fsPromises.unlink(tempFilePath).catch(() => {
                        console.log(`Warning: Temporary file ${tempFilePath} may still exist and could not be cleaned up.`);
                    });
                } else if (tmpStat) {
                    await fsPromises.unlink(tempFilePath).catch(() => {});
                }
            }
        } catch (_) {
            // ignore cleanup errors
        }
    }
}

// --- Utility helpers ---

function isExecutable(filePath) {
    try {
        fs.accessSync(filePath, fs.constants.X_OK);
        return true;
    } catch {
        return false;
    }
}

function fetchText(url) {
    return new Promise((resolve, reject) => {
        const client = url.protocol === "https:" ? https : http;
        client.get(url, { headers: { "User-Agent": "node" } }, (res) => {
            if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                return fetchText(new URL(res.headers.location, url.href)).then(resolve, reject);
            }
            if (res.statusCode !== 200) {
                res.resume();
                return reject(new Error(`HTTP ${res.statusCode}`));
            }
            let data = "";
            res.setEncoding("utf-8");
            res.on("data", (chunk) => data += chunk);
            res.on("end", () => resolve(data));
            res.on("error", reject);
        }).on("error", reject);
    });
}

function fetchUrl(url) {
    return new Promise((resolve, reject) => {
        const client = url.protocol === "https:" ? https : http;
        client.get(url, { headers: { "User-Agent": "node" } }, (res) => {
            resolve(res);
        }).on("error", reject);
    });
}

function execFileAsync(command, args) {
    return new Promise((resolve) => {
        execFile(command, args, (error, stdout, stderr) => {
            resolve({
                code: error ? error.code || 1 : 0,
                stdout: stdout || "",
                stderr: stderr || "",
            });
        });
    });
}

// Entry point
main();
