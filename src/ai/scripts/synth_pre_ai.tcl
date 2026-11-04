# HLS ROM initialization assets must be visible to readmemh from the run directory.
set ai_script_dir [file dirname [file normalize [info script]]]
set ai_asset_dir [file normalize [file join $ai_script_dir .. rtl cnn]]
foreach ai_asset [glob $ai_asset_dir/*.dat] {
    file copy -force $ai_asset [file join [pwd] [file tail $ai_asset]]
}
