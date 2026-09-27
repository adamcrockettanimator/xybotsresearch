#target photoshop

// Imports N_001.png ... N_030.png as ordered layers, then creates a frame
// animation with one timeline frame per layer.
(function () {
    var inputFolder = new Folder("D:/Godot/xybotsResearch/blender/renders/xybots_8dir/N");
    var outputFile = new File("D:/Godot/xybotsResearch/blender/renders/xybots_8dir/xybots_run_N_three_tone_frame_animation.psd");
    var files = inputFolder.getFiles(function (entry) {
        return entry instanceof File && /^N_\d{3}\.png$/i.test(entry.name);
    });
    files.sort(function (a, b) { return a.name.localeCompare(b.name); });
    if (files.length === 0) throw new Error("No N_###.png frames found in " + inputFolder.fsName);

    app.displayDialogs = DialogModes.NO;
    // The previous import document is a generated asset, not user artwork.
    // Close it so Photoshop will not reuse it when opening N_001.png again.
    for (var d = app.documents.length - 1; d >= 0; d--) {
        if (app.documents[d].name === "N_001.png" && app.documents[d].width.as("px") === 32 && app.documents[d].height.as("px") === 48) {
            app.documents[d].close(SaveOptions.DONOTSAVECHANGES);
        }
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
    // Initialise a frame-animation timeline, then map the ordered layer stack
    // to its frames. (The frame list begins with N_001 at the stack bottom.)
    executeAction(stringIDToTypeID("makeFrameAnimation"), undefined, DialogModes.NO);
    executeAction(stringIDToTypeID("animationFramesFromLayers"), new ActionDescriptor(), DialogModes.NO);

    var saveOptions = new PhotoshopSaveOptions();
    saveOptions.layers = true;
    doc.saveAs(outputFile, saveOptions, true, Extension.LOWERCASE);
}());
