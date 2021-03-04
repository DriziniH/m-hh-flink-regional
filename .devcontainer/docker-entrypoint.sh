#!/usr/bin/env bash

###############################################################################
#  Licensed to the Apache Software Foundation (ASF) under one
#  or more contributor license agreements.  See the NOTICE file
#  distributed with this work for additional information
#  regarding copyright ownership.  The ASF licenses this file
#  to you under the Apache License, Version 2.0 (the
#  "License"); you may not use this file except in compliance
#  with the License.  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

COMMAND_STANDALONE="standalone-job"
# Deprecated, should be remove in Flink release 1.13
COMMAND_NATIVE_KUBERNETES="native-k8s"
COMMAND_HISTORY_SERVER="history-server"

# If unspecified, the hostname of the container is taken as the JobManager address
JOB_MANAGER_RPC_ADDRESS=${JOB_MANAGER_RPC_ADDRESS:-$(hostname -f)}
CONF_FILE="${FLINK_HOME}/conf/flink-conf.yaml"

drop_privs_cmd() {
    if [ $(id -u) != 0 ]; then
        # Don't need to drop privs if EUID != 0
        return
    elif [ -x /sbin/su-exec ]; then
        # Alpine
        echo su-exec flink
    else
        # Others
        echo gosu flink
    fi
}

copy_plugins_if_required() {
  if [ -z "$ENABLE_BUILT_IN_PLUGINS" ]; then
    return 0
  fi

  echo "Enabling required built-in plugins"
  for target_plugin in $(echo "$ENABLE_BUILT_IN_PLUGINS" | tr ';' ' '); do
    echo "Linking ${target_plugin} to plugin directory"
    plugin_name=${target_plugin%.jar}

    mkdir -p "${FLINK_HOME}/plugins/${plugin_name}"
    if [ ! -e "${FLINK_HOME}/opt/${target_plugin}" ]; then
      echo "Plugin ${target_plugin} does not exist. Exiting."
      exit 1
    else
      ln -fs "${FLINK_HOME}/opt/${target_plugin}" "${FLINK_HOME}/plugins/${plugin_name}"
      echo "Successfully enabled ${target_plugin}"
    fi
  done
}

set_config_option() {
  local option=$1
  local value=$2

  # escape periods for usage in regular expressions
  local escaped_option=$(echo ${option} | sed -e "s/\./\\\./g")

  # either override an existing entry, or append a new one
  if grep -E "^${escaped_option}:.*" "${CONF_FILE}" > /dev/null; then
        sed -i -e "s/${escaped_option}:.*/$option: $value/g" "${CONF_FILE}"
  else
        echo "${option}: ${value}" >> "${CONF_FILE}"
  fi
}

prepare_configuration() {
    echo "Preparing configuration"
    set_config_option jobmanager.rpc.address ${JOB_MANAGER_RPC_ADDRESS}
    set_config_option blob.server.port 6124
    set_config_option query.server.port 6125
    set_config_option classloader.resolve-order parent-first

    TASK_MANAGER_NUMBER_OF_TASK_SLOTS=${TASK_MANAGER_NUMBER_OF_TASK_SLOTS:-1}
    set_config_option taskmanager.numberOfTaskSlots ${TASK_MANAGER_NUMBER_OF_TASK_SLOTS}

    if [ -n "${FLINK_PROPERTIES}" ]; then
        echo "${FLINK_PROPERTIES}" >> "${CONF_FILE}"
    fi
    envsubst < "${CONF_FILE}" > "${CONF_FILE}.tmp" && mv "${CONF_FILE}.tmp" "${CONF_FILE}"
}

maybe_enable_jemalloc() {
    if [ "${DISABLE_JEMALLOC:-false}" == "false" ]; then
        export LD_PRELOAD=$LD_PRELOAD:/usr/lib/x86_64-linux-gnu/libjemalloc.so
    fi
}

maybe_enable_jemalloc

copy_plugins_if_required

prepare_configuration

args=("$@")
if [ "$1" = "help" ]; then
    printf "Usage: $(basename "$0") (jobmanager|${COMMAND_STANDALONE}|taskmanager|${COMMAND_HISTORY_SERVER})\n"
    printf "    Or $(basename "$0") help\n\n"
    printf "By default, Flink image adopts jemalloc as default memory allocator. This behavior can be disabled by setting the 'DISABLE_JEMALLOC' environment variable to 'true'.\n"
    exit 0
elif [ "$1" = "jobmanager" ]; then
    args=("${args[@]:1}")

    echo "Starting Job Manager"

    exec $(drop_privs_cmd) "$FLINK_HOME/bin/jobmanager.sh" start-foreground "${args[@]}"
elif [ "$1" = ${COMMAND_STANDALONE} ]; then
    args=("${args[@]:1}")

    echo "Starting Job Manager"
 
    echo "$FLINK_HOME/bin/standalone-job.sh start-foreground --job-classname ${args[@]}"

    exec $(drop_privs_cmd) "$FLINK_HOME/bin/standalone-job.sh" start-foreground --job-classname "${args[@]}"    
    
elif [ "$1" = ${COMMAND_HISTORY_SERVER} ]; then
    args=("${args[@]:1}")

    echo "Starting History Server"

    exec $(drop_privs_cmd) "$FLINK_HOME/bin/historyserver.sh" start-foreground "${args[@]}"
elif [ "$1" = "taskmanager" ]; then
    args=("${args[@]:1}")

    echo "Starting Task Manager"

    exec $(drop_privs_cmd) "$FLINK_HOME/bin/taskmanager.sh" start-foreground "${args[@]}"
elif [ "$1" = "$COMMAND_NATIVE_KUBERNETES" ]; then
    args=("${args[@]:1}")

    export _FLINK_HOME_DETERMINED=true
    . $FLINK_HOME/bin/config.sh
    export FLINK_CLASSPATH="`constructFlinkClassPath`:$INTERNAL_HADOOP_CLASSPATHS"
    # Start commands for jobmanager and taskmanager are generated by Flink internally.
    echo "Start command: ${args[@]}"
    exec $(drop_privs_cmd) bash -c "${args[@]}"
fi

args=("${args[@]}")

# Set the Flink related environments
export _FLINK_HOME_DETERMINED=true
. $FLINK_HOME/bin/config.sh
export FLINK_CLASSPATH="`constructFlinkClassPath`:$INTERNAL_HADOOP_CLASSPATHS"

# Running command in pass-through mode
exec $(drop_privs_cmd) "${args[@]}"