#target photoshop

// Creates an editable frame animation from Cowboy1_RunN's North PNG sequence.
(function () {
    var inputFolder = new Folder("D:/Godot/xybotsResearch/blender/renders/cowboy1_runN_8dir_48/N");
    var outputFile = new File("D:/Godot/xybotsResearch/blender/renders/cowboy1_runN_8dir_48/cowboy1_runN_N_frame_animation.psd");
    var files = inputFolder.getFiles(function (entry) {
        return entry instanceof File && /^N_\d{3}\.png$/i.test(entry.name);
    });
    files.sort(function (a, b) { return a.name.localeCompare(b.name); });
    if (files.length !== 22) throw new Error("Expected N_000.png through N_021.png; found " + files.length + " frames.");

    app.displayDialogs = DialogModes.NO;
    // Prevent Photoshop from reusing an already-open source PNG document.
    for (var d = app.documents.length - 1; d >= 0; d--) {
        try {
            if (app.documents[d].fullName.fsName === files[0].fsName) {
                app.documents[d].close(SaveOptions.DONOTSAVECHANGES);
            }
        } catch (ignore) {}
    }

    var doc = app.open(files[0]);
    doc.activeLayer.name = files[0].name.replace(/\.png$/i, "");
    for (var i = 1; i < files.length; i++) {
        var frameDoc = app.open(files[i]);
        var importedLayer = frameDoc.activeLayer.duplicate(doc, ElementPlacement.PLACEATBEGINNING);
        app.activeDocument = doc;
        importedLayer.name = files[i].name.replace(/\.png$/i, "");
        app.activeDocument = frameDoc;
        frameDoc.close(SaveOptions.DONOTSAVECHANGES);
    }

    app.activeDocument = doc;
    executeAction(stringIDToTypeID("makeFrameAnimation"), undefined, DialogModes.NO);
    executeAction(stringIDToTypeID("animationFramesFromLayers"), new ActionDescriptor(), DialogModes.NO);
    var options = new PhotoshopSaveOptions();
    options.layers = true;
    doc.saveAs(outputFile, options, true, Extension.LOWERCASE);
}());
