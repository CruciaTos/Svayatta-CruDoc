module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:import/errors",
    "plugin:import/warnings",
    "plugin:import/typescript",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["tsconfig.json", "tsconfig.dev.json"],
    sourceType: "module",
  },
  ignorePatterns: [
    "/lib/**/*", // Ignore built files.
    "/generated/**/*", // Ignore generated files.
  ],
  plugins: [
    "@typescript-eslint",
    "import",
  ],
  rules: {
    "quotes": ["error", "double"],
    "import/no-unresolved": 0,
    "indent": ["error", 2],
    // Git normalises line endings; CRLF checkouts on Windows are fine.
    "linebreak-style": 0,
    // Long user-facing strings and URLs read better unwrapped.
    "max-len": ["error", {
      code: 120,
      ignoreStrings: true,
      ignoreTemplateLiterals: true,
      ignoreComments: true,
      ignoreUrls: true,
    }],
    // External payloads (WhatsApp, Gmail, Gemini) use snake_case keys.
    // The public Appointments API takes patient_name / doctor_id.
    "camelcase": ["error", {
      properties: "never",
      ignoreDestructuring: true,
      allow: ["^patient_name$", "^doctor_id$"],
    }],
    "require-jsdoc": 0,
    "valid-jsdoc": 0,
  },
};
