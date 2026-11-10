import pya

app=pya.Application.instance()
window=app.main_window()
window.load_layout('/project/design.gds',1)
view=window.current_view()
view.set_config('background-color','#0b1020')
view.set_config('grid-visible','false')
view.set_config('text-visible','false')
# Show upper routing layers rather than dense transistor/fill polygons.
view.clear_layers()
for layer,color in ((69,0x38bdf8),(70,0xfbbf24),(71,0x34d399),(72,0xc084fc)):
    properties=pya.LayerPropertiesNode()
    properties.source=f'{layer}/20@1'
    properties.name=f'met{layer-67}'
    properties.frame_color=color
    properties.fill_color=color
    properties.dither_pattern=0
    view.insert_layer(view.end_layers(),properties)
view.max_hier()
view.zoom_fit()
view.save_image('/output/layout.png',1400,1400)
app.exit(0)
