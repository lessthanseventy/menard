import { spawn } from "node:child_process";

export function run(
  cmd: string,
  args: string[],
  cwd: string,
  input?: string,
  env?: Record<string, string>,
): Promise<{ status: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args, {
      cwd,
      env: { ...process.env, ...env },
      stdio: [input === undefined ? "ignore" : "pipe", "pipe", "pipe"],
    });
    if (input !== undefined) proc.stdin?.end(input);
    let stdout = "";
    let stderr = "";
    proc.stdout?.on("data", (d: Buffer | string) => (stdout += d));
    proc.stderr?.on("data", (d: Buffer | string) => (stderr += d));
    proc.on("close", (status) => resolve({ status, stdout, stderr }));
    proc.on("error", reject);
  });
}

export function runQuiet(cmd: string, args: string[], cwd: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args, { cwd, stdio: "ignore" });
    proc.on("close", () => resolve());
    proc.on("error", reject);
  });
}