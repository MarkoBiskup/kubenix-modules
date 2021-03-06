{ name, lib, config, k8s, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.deployer.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Deployer image to use";
        type = types.str;
        default = "xtruder/deployer:latest";
      };

      runAsJob = mkOption {
        description = "Whether to run as job";
        type = types.bool;
        default = false;
      };

      exitOnError = mkOption {
        description = "Exit on error (do not atomatically retry)";
        type = types.bool;
        default = false;
      };

      exitOnSuccess = mkOption {
        description = "Exit on success";
        type = types.bool;
        default = false;
      };

      preventDestroy = mkOption {
        description = "Prevent destroy (do not atomatically destroy resources)";
        type = types.bool;
        default = true;
      };

      configuration =  mkOption {
        description = "Terraform configuration";
        type = mkOptionType {
          name = "deepAttrs";
          description = "deep attribute set";
          check = isAttrs;
          merge = loc: foldl' (res: def: recursiveUpdate res def.value) {};
        };
        default = {};
      };

      logLevel = mkOption {
        description = "Terraform log level";
        type = types.nullOr (types.enum ["TRACE" "DEBUG" "INFO" "WARN" "ERROR"]);
        default = null;
      };

      vars = mkOption {
        description = "Additional environment variables to set";
        type = types.attrsOf types.attrs;
        default = {};
      };
    };

    config = {
      exitOnError = mkDefault config.runAsJob;
      exitOnSuccess = mkDefault config.runAsJob;

      kubernetes.resources.${if config.runAsJob then "jobs" else "deployments"}.deployer = mkMerge [{
        metadata.name = name;
        metadata.labels.app = name;
        spec.selector.matchLabels.app = mkIf (!config.runAsJob) name;
        spec.template = {
          metadata.labels.app = name;
          spec = {
            restartPolicy = mkIf config.runAsJob "Never";
            serviceAccountName = name;
            containers.deployer = {
              image = config.image;
              imagePullPolicy = "Always";
              env = {
                EXIT_ON_ERROR = mkIf config.exitOnError {value = "1";};
                EXIT_ON_SUCCESS = mkIf config.exitOnSuccess {value = "1";};
                TF_LOG = mkIf (config.logLevel != null) {value = config.logLevel;};
              } // mapAttrs' (name: value: nameValuePair "TF_VAR_${name}" value) config.vars;
              volumeMounts = [{
                name = "resources";
                mountPath = "/usr/local/deployer/inputs";
              }];
              resources = {
                requests.memory = "100Mi";
                requests.cpu = "100m";
              };
            };
            volumes.resources.configMap.name = name;
          };
        };
      } (optionalAttrs config.runAsJob {
        spec.backoffLimit = 100;
      }) (optionalAttrs (!config.runAsJob) {
        spec.strategy.type = "Recreate";
      })];

      kubernetes.resources.configMaps.deployer = {
        metadata.name = name;
        metadata.labels.app = name;
        data."main.tf.json" = builtins.toJSON
          (filterAttrs (n: v: v != [] && v != {}) config.configuration);
      };

      kubernetes.resources.serviceAccounts.deployer = {
        metadata.name = name;
        metadata.labels.app = name;
      };
    };
  };
}
