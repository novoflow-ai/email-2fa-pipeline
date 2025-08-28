#!/bin/bash
# Package Lambda functions for deployment

cd "$(dirname "$0")/lambda"

# Package parser
cp parser.js index.js
zip -q parser.zip index.js
rm index.js
echo "✓ Packaged parser.zip"

# Package lookup
cp lookup.js index.js
zip -q lookup.zip index.js
rm index.js
echo "✓ Packaged lookup.zip"

echo "Done! Lambda functions packaged."