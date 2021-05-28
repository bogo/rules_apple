# Copyright 2021 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Partial implementation for Apple .symbols file processing."""

load(
    "@build_bazel_apple_support//lib:apple_support.bzl",
    "apple_support",
)
load(
    "@build_bazel_rules_apple//apple:providers.bzl",
    "AppleFrameworkImportInfo",
)
load(
    "@build_bazel_rules_apple//apple/internal:intermediates.bzl",
    "intermediates",
)
load(
    "@build_bazel_rules_apple//apple/internal:processor.bzl",
    "processor",
)
load(
    "@bazel_skylib//lib:partial.bzl",
    "partial",
)
load("@bazel_skylib//lib:shell.bzl", "shell")

_AppleSymbolsFileInfo = provider(
    doc = "Private provider to propagate the transitive .symbols `File`s.",
    fields = {
        "symbols_output_dirs": "Depset of `File`s containing directories of $UUID.symbols files for transitive dependencies.",
    },
)

def _apple_symbols_file_partial_impl(
        *,
        actions,
        binary_artifact,
        debug_outputs_provider,
        dependency_targets,
        label_name,
        include_symbols_in_bundle,
        platform_prerequisites):
    """Implementation for the Apple .symbols file processing partial."""
    outputs = []
    if (platform_prerequisites.cpp_fragment.apple_generate_dsym and
        binary_artifact and debug_outputs_provider):
        inputs = [binary_artifact]
        for debug_output in debug_outputs_provider.outputs_map.values():
            inputs.append(debug_output["dsym_binary"])
        for target in dependency_targets:
            if AppleFrameworkImportInfo in target:
                inputs.extend(target[AppleFrameworkImportInfo].debug_info_binaries.to_list())
        output = intermediates.directory(actions, label_name, "symbols_output")
        outputs.append(output)
        apple_support.run_shell(
            actions = actions,
            apple_fragment = platform_prerequisites.apple_fragment,
            inputs = inputs,
            outputs = [output],
            command = (
                "mkdir -p {output} && /usr/bin/xcrun symbols -noTextInSOD " +
                "-noDaemon -arch all -symbolsPackageDir {output} {inputs} >/dev/null"
            ).format(
                output = shell.quote(output.path),
                inputs = " ".join([shell.quote(i.path) for i in inputs]),
            ),
            mnemonic = "GenerateAppleSymbolsFile",
            xcode_config = platform_prerequisites.xcode_version_config,
        )

    transitive_output_files = depset(
        direct = outputs,
        transitive = [
            x[_AppleSymbolsFileInfo].symbols_output_dirs
            for x in dependency_targets
            if _AppleSymbolsFileInfo in x
        ],
    )

    if include_symbols_in_bundle:
        bundle_files = [(processor.location.archive, "Symbols", transitive_output_files)]
    else:
        bundle_files = []

    return struct(
        bundle_files = bundle_files,
        providers = [_AppleSymbolsFileInfo(symbols_output_dirs = transitive_output_files)],
    )

def apple_symbols_file_partial(
        *,
        actions,
        binary_artifact,
        debug_outputs_provider,
        dependency_targets = [],
        label_name,
        include_symbols_in_bundle,
        platform_prerequisites):
    """Constructor for the Apple .symbols package processing partial.

    Args:
      actions: Actions defined for the current build context.
      binary_artifact: The main binary artifact for this target.
      debug_outputs_provider: The AppleDebugOutputs provider containing the references to the debug
        outputs of this target's binary.
      dependency_targets: List of targets that should be checked for files that need to be
        bundled.
      label_name: Name of the target being built.
      include_symbols_in_bundle: Whether the partial should package in its bundle
        the .symbols files for this binary plus all binaries in `dependency_targets`.
      platform_prerequisites: Struct containing information on the platform being targeted.

    Returns:
      A partial that returns the .symbols files to propagate or bundle, if any were requested.
    """
    return partial.make(
        _apple_symbols_file_partial_impl,
        actions = actions,
        binary_artifact = binary_artifact,
        debug_outputs_provider = debug_outputs_provider,
        dependency_targets = dependency_targets,
        label_name = label_name,
        include_symbols_in_bundle = include_symbols_in_bundle,
        platform_prerequisites = platform_prerequisites,
    )
