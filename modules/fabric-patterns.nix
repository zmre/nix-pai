# Fabric patterns processing module
# Creates a derivation containing patterns and a generated patterns list
{
  pkgs,
  lib,
  patternsSource,
}: let
  # Script to generate patterns list from pattern directories
  generatePatternsListScript = pkgs.writeShellScript "generate-patterns-list" ''
    set -euo pipefail
    PATTERNS_DIR="$1"
    OUTPUT_FILE="$2"

    PATTERNS_LIST=""
    for pattern_dir in "$PATTERNS_DIR"/*/; do
      [ -d "$pattern_dir" ] || continue
      pattern_name=$(basename "$pattern_dir")
      system_file="$pattern_dir/system.md"

      if [ -f "$system_file" ]; then
        # Extract first meaningful line after "# IDENTITY" or use pattern name
        description=$(${pkgs.gawk}/bin/awk '
          /^# IDENTITY/ { found=1; next }
          found && /^[^#]/ && NF > 0 {
            gsub(/^[ \t]+|[ \t]+$/, "")
            print
            exit
          }
        ' "$system_file" | head -c 100)

        if [ -z "$description" ]; then
          description="Apply $pattern_name pattern"
        fi
        PATTERNS_LIST="$PATTERNS_LIST- \`$pattern_name\` - $description
"
      fi
    done

    echo "$PATTERNS_LIST" > "$OUTPUT_FILE"
  '';
in
  pkgs.runCommand "fabric-patterns" {
    inherit patternsSource;
  } ''
    mkdir -p $out/patterns
    mkdir -p $out

    # Copy patterns to output
    cp -R ${patternsSource}/* $out/patterns/

    # Generate patterns list
    ${generatePatternsListScript} $out/patterns $out/patterns-list.txt
  ''
