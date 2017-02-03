/*++

Copyright (c) 2017 Minoca Corp.

    This file is licensed under the terms of the GNU General Public License
    version 3. Alternative licensing terms are available. Contact
    info@minocacorp.com for details. See the LICENSE file at the root of this
    project for complete licensing information.

Module Name:

    ninja.ck

Abstract:

    This module implements support for outputting Ninja files from the Minoca
    build generator specification.

Author:

    Evan Green 2-Feb-2017

Environment:

    Chalk

--*/

//
// ------------------------------------------------------------------- Includes
//

from io import open;

//
// --------------------------------------------------------------------- Macros
//

//
// ---------------------------------------------------------------- Definitions
//

//
// ------------------------------------------------------ Data Type Definitions
//

//
// ----------------------------------------------- Internal Function Prototypes
//

function
_ninjaPrintConfig (
    file,
    config,
    variables,
    target
    );

function
_ninjaPrintInputs (
    file,
    config,
    inputs
    );

function
_ninjaPrintRebuildRule (
    file,
    config,
    scripts
    );

function
_ninjaPrintRebuildCommand (
    file,
    config
    );

function
_ninjaPrintDefaultTargets (
    file,
    config,
    targets
    );

function
_ninjaPrintTargetFile (
    file,
    config,
    target
    );

function
_ninjaPrintPath (
    file,
    config,
    path
    );

function
_ninjaPrintConfigValue (
    file,
    value
    );

function
_ninjaPrintWithVariableConversion (
    file,
    value
    );

//
// -------------------------------------------------------------------- Globals
//

var _ninjaLineContinuation = " $\n        ";

//
// ------------------------------------------------------------------ Functions
//

class NinjaVariableTransformer {
    function
    __get (
        key
        )

    /*++

    Routine Description:

        This routine performs a "get" operation on this fake dictionary, which
        really returns a dressed up version of the key.

    Arguments:

        key - Supplies the key to get.

    Return Value:

        Retuns the variable specified for a Makefile.

    --*/

    {

        if ((key == "IN") || (key == "in")) {
            return "$in";

        } else if ((key == "OUT") || (key == "out")) {
            return "$out";
        }

        return "${%s}" % key;
    }

    function
    __slice (
        key
        )

    /*++

    Routine Description:

        This routine executes the slice operator, which is called when square
        brackets are used.

    Arguments:

        key - Supplies the key to get.

    Return Value:

        Retuns the variable specified for a Makefile.

    --*/

    {

        return this.__get(key);
    }
}

function
buildNinja (
    config,
    entries
    )

/*++

Routine Description:

    This routine creates a Ninja file from the given Minoca build generator
    specification.

Arguments:

    config - Supplies the application configuration

    entries - Supplies a dictionary containing the tools, targets, pools, and
        build directories.

Return Value:

    0 on success.

    1 on failure.

--*/

{

    var file;
    var module;
    var ninjaPath;
    var pools;
    var targetsList = entries.targetsList;
    var tools;
    var totalInputs;

    ninjaPath = config.output + "/build.ninja";
    if (config.verbose) {
        Core.print("Creating %s" % ninjaPath);
    }

    file = open(ninjaPath, "wb");

    //
    // TODO: Put the current time in the file.
    //

    file.write("# Ninja build automatically generated by Minoca mingen\n");
    file.write("# Define high level variables\n");
    file.write("%s = %s\n" % [config.input_variable, config.input]);
    file.write("%s = %s\n" % [config.output_variable, config.output]);
    _ninjaPrintConfig(file, config, config.vars, null);
    file.write("\n# Define tools\n");
    tools = entries.tools;
    for (tool in tools) {
        tool = tools[tool];
        if (!tool.active) {
            continue;
        }

        file.write("rule %s\n" % tool.name);
        if (tool.description) {
            file.write("    description = ");
            _ninjaPrintWithVariableConversion(file, tool.description);
            file.write("\n");
        }

        file.write("    command = ");
        _ninjaPrintWithVariableConversion(file, tool.command);
        file.write("\n");
        if (tool.get("depfile")) {
            file.write("    depfile = ");
            _ninjaPrintWithVariableConversion(file, tool.depfile);
            file.write("\n");
        }

        if (tool.get("depsformat")) {
            file.write("    deps = ");
            _ninjaPrintWithVariableConversion(file, tool.depsformat);
            file.write("\n");
        }

        if (tool.get("pool")) {
            file.write("    pool = ");
            _ninjaPrintWithVariableConversion(file, tool.pool);
            file.write("\n");
        }

        file.write("\n");
    }

    pools = entries.pools;
    if (pools.length()) {
        file.write("# Define pools");
        for (pool in pools) {
            if (!pool.active) {
                continue;
            }

            file.write("\npool %s\n    depth = %d\n" %
                       [pool.name, pool.depth]);
        }
    }

    file.write("\n");

    //
    // Loop over and print every active target.
    //

    targetsList = entries.targetsList;
    for (target in targetsList) {
        if (!target.active) {
            continue;
        }

        if (target.module != module) {
            module = target.module;
            if (module == "") {
                file.write("# Define root targets\n");

            } else {
                file.write("# Define targets for %s\n" % module);
            }
        }

        file.write("build ");
        _ninjaPrintTargetFile(file, config, target);
        file.write(": %s " % target.tool);
        _ninjaPrintInputs(file, config, target.inputs);
        if (target.implicit.length()) {
            file.write(_ninjaLineContinuation + " | ");
            _ninjaPrintInputs(file, config, target.implicit);
        }

        if (target.orderonly.length()) {
            file.write(_ninjaLineContinuation + " || ");
            _ninjaPrintInputs(file, config, target.orderonly);
        }

        file.write("\n");
        _ninjaPrintConfig(file, config, target.config, target);
        if (target.get("pool")) {
            file.write("    pool = %s\n" % target.pool);
        }

        //
        // Separate targets with newlines, except squeeze together a bunch of
        // one-liners.
        //

        totalInputs = target.inputs.length() + target.implicit.length() +
                      target.orderonly.length();


        if ((totalInputs > 1) ||
            (target.config.length()) ||
            (target.get("pool"))) {

            file.write("\n");
        }
    }

    if (config.generator) {
        _ninjaPrintRebuildRule(file, config, entries.scripts);
    }

    _ninjaPrintDefaultTargets(file, config, targetsList);
    file.close();
    return;
}

//
// --------------------------------------------------------- Internal Functions
//

function
_ninjaPrintConfig (
    file,
    config,
    variables,
    target
    )

/*++

Routine Description:

    This routine writes a target's variables dictionary to the output file.

Arguments:

    file - Supplies the output file being written.

    config - Supplies the application configuration

    variables - Supplies the variables to print.

    target - Supplies an optional target being printed.

Return Value:

    None.

--*/

{

    for (key in variables) {
        if (target) {
            file.write("    ");
        }

        file.write("%s = " % key);
        _ninjaPrintConfigValue(file, variables[key]);
        file.write("\n");
    }

    return;
}

function
_ninjaPrintInputs (
    file,
    config,
    inputs
    )

/*++

Routine Description:

    This routine prints one of the inputs list for a target.

Arguments:

    file - Supplies the file being printed to.

    config - Supplies the application configuration

    inputs - Supplies the list of inputs to print.

Return Value:

    None.

--*/

{

    var index;
    var input;
    var length;

    length = inputs.length();
    for (index = 0; index < length; index += 1) {
        input = inputs[index];
        if (input is String) {
            _ninjaPrintPath(file, config, input);

        } else {
            _ninjaPrintTargetFile(file, config, input);
        }

        if (index != length - 1) {
            file.write(_ninjaLineContinuation);
        }
    }

    return;
}

function
_ninjaPrintRebuildRule (
    file,
    config,
    scripts
    )

/*++

Routine Description:

    This routine emits the built in target that rebuilds the Makefile itself
    based on the source scripts.

Arguments:

    file - Supplies the file being printed to.

    config - Supplies the application configuration

    scripts - Supplies a pointer to the list of scripts.

Return Value:

    None.

--*/

{

    var count;
    var index;

    file.write("\n# Built-in tool and rule for rebuilding the ninja file "
               "itself.\n");

    file.write("rule rebuild_ninja\n"
               "    description = Rebuilding Ninja file\n"
               "    generator = 1\n"
               "    command = ");

    _ninjaPrintRebuildCommand(file, config);
    file.write("\n\nbuild %s: rebuild_ninja " % "build.ninja");
    count = scripts.length();
    index = 0;
    for (script in scripts) {
        file.write("${%s}/%s" % [config.input_variable, script]);
        if (index != count - 1) {
            file.write(_ninjaLineContinuation);
        }

        index += 1;
    }

    file.write("\n");
    return;
}

function
_ninjaPrintRebuildCommand (
    file,
    config
    )

/*++

Routine Description:

    This routine prints the command that can be used to rebuild the
    configuration.

Arguments:

    file - Supplies the file being printed to.

    config - Supplies the application configuration

Return Value:

    None.

--*/

{

    var args;

    //
    // Putting input, output, and format first will cause later specifications
    // of the same type to be ignored.
    //

    file.write("%s --input=\"$(%s)\" --output=\"$(%s)\" --format=%s" %
               [config.argv[0],
                config.input_variable,
                config.output_variable,
                "ninja"]);

    args = config.argv[1...-1];
    for (arg in args) {
        file.write(" " + arg);
    }

    return;
}

function
_ninjaPrintDefaultTargets (
    file,
    config,
    targets
    )

/*++

Routine Description:

    This routine prints any targets marked as default.

Arguments:

    file - Supplies the file being printed to.

    config - Supplies the application configuration

    targets - Supplies the set of targets.

Return Value:

    None.

--*/

{

    var printedBanner = false;

    for (target in targets) {
        if ((target.active) && (target.get("default"))) {
            if (!printedBanner) {
                file.write("\n# Default target\n");
                printedBanner = true;
            }

            file.write("default ");
            _ninjaPrintTargetFile(file, config, target);
            file.write("\n");
        }
    }

    if (printedBanner) {
        file.write("\n");
    }

    return;
}

function
_ninjaPrintTargetFile (
    file,
    config,
    target
    )

/*++

Routine Description:

    This routine writes a target's output file name to the output file.

Arguments:

    file - Supplies the output file being written.

    config - Supplies the application configuration

    target - Supplies an optional target being printed.

Return Value:

    None.

--*/

{

    var tool = target.get("tool");;

    if ((tool != null) && (tool == "phony")) {
        _ninjaPrintWithVariableConversion(file, target.output);
        return;
    }

    _ninjaPrintPath(file, config, target.output);
    return;
}

function
_ninjaPrintPath (
    file,
    config,
    path
    )

/*++

Routine Description:

    This routine prints a path.

Arguments:

    file - Supplies the output file being written.

    config - Supplies the application configuration

    path - Supplies the path to print.

Return Value:

    None.

--*/

{

    _ninjaPrintWithVariableConversion(file, path);
    return;
}

function
_ninjaPrintConfigValue (
    file,
    value
    )

/*++

Routine Description:

    This routine prints a configuration value.

Arguments:

    file - Supplies a pointer to the file to print to.

    value - Supplies a pointer to the object to print.

Return Value:

    0 on success.

    -1 if some entries were skipped.

--*/

{

    var index;
    var length;

    if (value is List) {
        length = value.length();
        for (index = 0; index < length; index += 1) {
            _ninjaPrintConfigValue(file, value[index]);
            if (index != length - 1) {
                file.write(" ");
            }
        }

    } else if (value is Int) {
        file.write("%d" % value);

    } else if (value is String) {
        _ninjaPrintWithVariableConversion(file, value);
    }

    return;
}

function
_ninjaPrintWithVariableConversion (
    file,
    value
    )

/*++

Routine Description:

    This routine prints a string to the output file, converting variable
    expressions into proper ninja format.

Arguments:

    file - Supplies a pointer to the file to print to.

    value - Supplies the value to convert.

Return Value:

    None.

--*/

{

    var result;

    try {
        result = value.template(NinjaVariableTransformer(), false);

    } except ValueError {
        Core.raise(ValueError("Error transforming string: \"%s\"" % value));
    }

    file.write(result);
    return;
}

