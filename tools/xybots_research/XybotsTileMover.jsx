#target photoshop
#targetengine "xybotsTileMover"

(function () {
    try {
    var TILE = 8;
    var state = {
        topRowY: null,
        copy: null,
        paste: null,
        junk: null
    };

    function px(value) {
        return Math.round(value.as("px"));
    }

    function pointText(point) {
        if (!point) {
            return "--";
        }
        return point.x + "," + point.y;
    }

    function fail(message) {
        alert(message);
        throw new Error(message);
    }

    function requireDocument() {
        if (!app.documents.length) {
            fail("Open the Photoshop document first.");
        }
        return app.activeDocument;
    }

    function selectedTile() {
        var doc = requireDocument();
        var bounds;

        try {
            bounds = doc.selection.bounds;
        } catch (error) {
            fail("Select an 8x8 tile with the rectangular marquee first.");
        }

        return {
            x: px(bounds[0]),
            y: px(bounds[1])
        };
    }

    function selectTile(point) {
        var doc = requireDocument();
        doc.selection.select([
            [point.x, point.y],
            [point.x + TILE, point.y],
            [point.x + TILE, point.y + TILE],
            [point.x, point.y + TILE]
        ]);
    }

    function copyTileTo(source, target) {
        var doc = requireDocument();

        selectTile(source);
        doc.selection.copy(false);
        doc.selection.clear();

        selectTile(target);
        var pastedLayer = doc.paste();
        doc.activeLayer = pastedLayer;

        var bounds = pastedLayer.bounds;
        var dx = target.x - px(bounds[0]);
        var dy = target.y - px(bounds[1]);
        pastedLayer.translate(dx, dy);

        doc.activeLayer = pastedLayer.merge();
    }

    function requirePoint(name, point) {
        if (!point) {
            fail("Set " + name + " first.");
        }
    }

    function updateStatus() {
        status.text =
            "Copy " + pointText(state.copy) +
            "   Paste " + pointText(state.paste) +
            "   TopY " + (state.topRowY === null ? "--" : state.topRowY) +
            "   Junk " + pointText(state.junk);
    }

    function setFromSelection(field) {
        state[field] = selectedTile();
        if (field === "paste" && state.topRowY === null) {
            state.topRowY = state.paste.y;
        }
        updateStatus();
    }

    function buildWindow() {
        var win = new Window("palette", "Xybots Tile Mover");
        win.orientation = "column";
        win.alignChildren = ["fill", "top"];
        win.spacing = 6;
        win.margins = 8;

        var row1 = win.add("group");
        row1.orientation = "row";
        row1.alignChildren = ["fill", "center"];

        var row2 = win.add("group");
        row2.orientation = "row";
        row2.alignChildren = ["fill", "center"];

        var row3 = win.add("group");
        row3.orientation = "row";
        row3.alignChildren = ["fill", "center"];

        var setTop = row1.add("button", undefined, "SetTop");
        var setCopy = row1.add("button", undefined, "SetCopy");
        var setPaste = row1.add("button", undefined, "SetPaste");

        var move = row2.add("button", undefined, "Move");
        var ret = row2.add("button", undefined, "Return");

        var setJunk = row3.add("button", undefined, "SetJunk");
        var junk = row3.add("button", undefined, "Junk");

        status = win.add("statictext", undefined, "", { multiline: true });
        status.preferredSize = [330, 34];

        var hint = win.add("statictext", undefined, "Set buttons use the current marquee selection.");
        hint.preferredSize = [330, 18];

        setTop.onClick = function () {
            var point = selectedTile();
            state.topRowY = point.y;
            if (!state.paste) {
                state.paste = { x: point.x, y: point.y };
            }
            updateStatus();
        };

        setCopy.onClick = function () {
            setFromSelection("copy");
        };

        setPaste.onClick = function () {
            setFromSelection("paste");
        };

        move.onClick = function () {
            requirePoint("Copy", state.copy);
            requirePoint("Paste", state.paste);

            copyTileTo(state.copy, state.paste);
            state.copy.x += TILE;
            state.paste.y += TILE;
            selectTile(state.copy);
            updateStatus();
        };

        ret.onClick = function () {
            requirePoint("Paste", state.paste);
            if (state.topRowY === null) {
                state.topRowY = state.paste.y;
            }

            state.paste.x += TILE;
            state.paste.y = state.topRowY;
            selectTile(state.paste);
            updateStatus();
        };

        setJunk.onClick = function () {
            setFromSelection("junk");
        };

        junk.onClick = function () {
            requirePoint("Copy", state.copy);
            requirePoint("Junk", state.junk);

            copyTileTo(state.copy, state.junk);
            state.copy.x += TILE;
            state.junk.x += TILE;
            selectTile(state.copy);
            updateStatus();
        };

        updateStatus();
        return win;
    }

    var status;
    if ($.global.xybotsTileMoverWindow && $.global.xybotsTileMoverWindow.visible) {
        $.global.xybotsTileMoverWindow.active = true;
        return;
    }

    $.global.xybotsTileMoverWindow = buildWindow();
    $.global.xybotsTileMoverWindow.center();
    $.global.xybotsTileMoverWindow.show();
    } catch (error) {
        alert("Xybots Tile Mover failed:\n\n" + error.message + "\n\nLine: " + error.line);
    }
})();
