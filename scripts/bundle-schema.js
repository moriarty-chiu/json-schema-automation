// scripts/bundle-schema.js
const $RefParser = require('@apidevtools/json-schema-ref-parser');
const fs = require('fs');
const path = require('path');

const inputSchemaPath = path.resolve(__dirname, '../schemas/dedicated-schema.json');
const outputSchemaPath = path.resolve(__dirname, '../schemas/render-schema.json');

$RefParser.bundle(inputSchemaPath)
    .then(schema => {
        fs.writeFileSync(outputSchemaPath, JSON.stringify(schema, null, 2));
        console.log('✅ Schema bundled successfully to render-schema.json');
    })
    .catch(err => {
        console.error('❌ Failed to bundle schema:', err);
        process.exit(1);
    });
