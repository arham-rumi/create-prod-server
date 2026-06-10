module.exports = {
  apps: [
    {
      name: "{{APP_NAME}}",
      script: "index.js",        // change to your entry point if needed
      instances: "max",          // use all CPU cores
      exec_mode: "cluster",
      watch: false,
      env: {
        NODE_ENV: "production",
        PORT: {{APP_PORT}},
      },
      // Restart policy
      max_memory_restart: "500M",
      restart_delay: 3000,
      max_restarts: 10,
      // Logging
      out_file: "./logs/out.log",
      error_file: "./logs/error.log",
      merge_logs: true,
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
    },
  ],
};
