#!/usr/bin/env node

import inquirer from "inquirer";
import chalk from "chalk";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const TEMPLATES_DIR = path.join(__dirname, "templates");

function fill(template, vars) {
  return template.replace(
    /\{\{(\w+)\}\}/g,
    (_, key) => vars[key] ?? `{{${key}}}`,
  );
}

function writeOutput(outputDir, filename, content) {
  fs.mkdirSync(outputDir, { recursive: true });
  fs.writeFileSync(path.join(outputDir, filename), content, "utf8");
}

async function main() {
  console.log();
  console.log(chalk.bold.cyan("  create-prod-server"));
  console.log(
    chalk.gray("  Scaffold your production VPS config in seconds.\n"),
  );

  const answers = await inquirer.prompt([
    {
      type: "input",
      name: "domain",
      message: "Domain name",
      default: "example.com",
      validate: (v) => (v.trim() ? true : "Domain is required"),
    },
    {
      type: "input",
      name: "appName",
      message: "App name",
      default: "my-app",
      validate: (v) =>
        /^[a-z0-9-_]+$/i.test(v.trim())
          ? true
          : "Use letters, numbers, hyphens, or underscores",
    },
    {
      type: "input",
      name: "appPort",
      message: "Local port your Node app listens on",
      default: "3000",
      validate: (v) =>
        /^\d+$/.test(v.trim()) && +v > 0 && +v < 65536
          ? true
          : "Enter a valid port number",
    },
    {
      type: "input",
      name: "nodeVersion",
      message: "Node.js version to install via NVM",
      default: "20",
      validate: (v) =>
        /^\d+(\.\d+)*$/.test(v.trim())
          ? true
          : "Enter a version like 20 or 20.11.0",
    },
  ]);

  const vars = {
    DOMAIN: answers.domain.trim(),
    APP_NAME: answers.appName.trim(),
    APP_PORT: answers.appPort.trim(),
    NODE_VERSION: answers.nodeVersion.trim(),
  };

  const outputDir = path.join(process.cwd(), vars.APP_NAME + "-server-config");

  const files = [
    { template: "nginx.conf", output: "nginx.conf" },
    { template: "ecosystem.config.js", output: "ecosystem.config.js" },
    { template: ".env.example", output: ".env.example" },
    { template: "setup.sh", output: "setup.sh" },
  ];

  console.log();

  for (const { template, output } of files) {
    const raw = fs.readFileSync(path.join(TEMPLATES_DIR, template), "utf8");
    const rendered = fill(raw, vars);
    writeOutput(outputDir, output, rendered);
    console.log(chalk.green("  ✔"), chalk.white(output));
  }

  // chmod is a no-op on Windows but doesn't error; Linux/mac VPS users benefit
  try {
    fs.chmodSync(path.join(outputDir, "setup.sh"), 0o755);
  } catch {
    /* ignore on Windows */
  }

  console.log();
  console.log(
    chalk.bold("  Done! Your config is in:"),
    chalk.cyan(`./${vars.APP_NAME}-server-config/`),
  );
  console.log();
  console.log(chalk.gray("  Next steps:"));
  console.log(chalk.gray("  1. Copy the folder to your VPS"));
  console.log(chalk.gray(`  2. Run: bash setup.sh`));
  console.log(
    chalk.gray(
      `  3. Copy nginx.conf to /etc/nginx/sites-available/${vars.DOMAIN}`,
    ),
  );
  console.log(
    chalk.gray(
      "  4. Copy ecosystem.config.js to your app root and run: pm2 start ecosystem.config.js",
    ),
  );
  console.log();
}

main().catch((err) => {
  console.error(chalk.red("\n  Error:"), err.message);
  process.exit(1);
});
