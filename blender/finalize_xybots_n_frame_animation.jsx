#target photoshop

// Converts the current ordered Xybots N layer stack into a Photoshop frame
// animation and saves it as an editable PSD.
(function () {
    var doc = app.activeDocument;
    if (doc.layers.length !== 30) throw new Error("Expected 30 imported frame layers; found " + doc.layers.length + ".");
    app.displayDialogs = DialogModes.NO;
    executeAction(stringIDToTypeID("makeFrameAnimation"), undefined, DialogModes.NO);
    executeAction(stringIDToTypeID("animationFramesFromLayers"), new ActionDescriptor(), DialogModes.NO);
    var outputFile = new File("D:/Godot/xybotsResearch/blender/renders/xybots_8dir/xybots_run_N_frame_animation.psd");
    var options = new PhotoshopSaveOptions();
    options.layers = true;
    doc.saveAs(outputFile, options, true, Extension.LOWERCASE);
    alert("Saved " + outputFile.fsName + " with 30 animation frames.");
}());
