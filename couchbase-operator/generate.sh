#!/bin/bash
# Helper script to automatically update the values.yaml and README.md from the CRD.
#
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function extractContents() {
    awk '
    BEGIN { found = 0; }
    /START/ {
        if (!found) {
            found = 1;
            $0 = substr($0, index($0, "==== START ====") + 16);
        }
    }
    /END/ {
        if (found) {
            found = 2;
            $0 = substr($0, 0, index($0, "==== END ====") - 1);
        }
    }   
        { if (found) {
            print;
            if (found == 2)
                found = 0;
        }
    }
    ' "$1"
}

# Defaults to everything required locally but useful for testing to have configuration options
CRD_FILE=${CRD_FILE:-$SCRIPT_DIR/crds/couchbase.crds.yaml}
CHART_DIR=${CHART_DIR:-$SCRIPT_DIR}
OUTPUT_DIR=${OUTPUT_DIR:-$SCRIPT_DIR}
OUTPUT_VALUES_FILE=${OUTPUT_VALUES_FILE:-$OUTPUT_DIR/values.yaml}
OUTPUT_README_FILE=${OUTPUT_README_FILE:-$OUTPUT_DIR/README.md}
MIN_K8S_VERSION=${MIN_K8S_VERSION:-17}

TEMP_FILE=$(mktemp)

# First add the manually controlled source
cat "${SCRIPT_DIR}/values.yamltmpl" > "${OUTPUT_VALUES_FILE}"
# Now autogenerate the rest of the values file
CRD_FILE=${CRD_FILE} /bin/bash "${SCRIPT_DIR}/../tools/value-generation/generateValuesFile.sh" --format=full > "${TEMP_FILE}"
extractContents "${TEMP_FILE}" >> "${OUTPUT_VALUES_FILE}"
# Use this to generate the Markdown documentation
CHART_DIR=${CHART_DIR} OUTPUT_FILE=${TEMP_FILE} /bin/bash "${SCRIPT_DIR}/../tools/value-generation/generateDocumentation.sh" > "${TEMP_FILE}"

# Now just remove lines matching the following as they're really long winded defaults
extractContents "${TEMP_FILE}" | grep -Ev 'cluster.backup |cluster.cluster |cluster.logging |cluster.logging.audit |cluster.logging.server |cluster.networking |cluster.networking.tls |cluster.security | cluster.security.ldap |cluster.securityContext |cluster.servers |cluster.servers.default | cluster.servers.default.env | cluster.servers.default.envFrom | cluster.servers.default.pod |syncGateway.config |syncGateway.config.databases ' > "${OUTPUT_README_FILE}"

# Asciidoc helper
CHART_DIR=${CHART_DIR} /bin/bash "${SCRIPT_DIR}/../tools/value-generation/generateDocumentation.sh" --template-files=README.adoc.gotmpl > "${TEMP_FILE}"
# Have to remove the trailing | and the markdown header divider
extractContents "${TEMP_FILE}" | sed 's/|$//' | sed '/^|-.*$/d' > "${OUTPUT_README_FILE}".adoc

# For K8S versions prior to 1.20 we have to reduce the generated set as non-nullable fields are not defaulted:
# https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#defaulting-and-nullable
if [[ $MIN_K8S_VERSION -lt 20 ]]; then
    echo "Generating reduced set to support Kubernetes version 1.$MIN_K8S_VERSION"
    # Copy over the current full set
    mv -f "${OUTPUT_VALUES_FILE}" "${OUTPUT_VALUES_FILE%%.yaml}-all.yaml"
    cat "${SCRIPT_DIR}/values.yamltmpl" > "${OUTPUT_VALUES_FILE}"
    # Once we only support 1.20+, remove this additional call
    CRD_FILE=${CRD_FILE} /bin/bash "${SCRIPT_DIR}/../tools/value-generation/generateValuesFile.sh" --format=min > "${TEMP_FILE}"
    extractContents "${TEMP_FILE}" >> "${OUTPUT_VALUES_FILE}"
fi
rm -f "${TEMP_FILE}"
