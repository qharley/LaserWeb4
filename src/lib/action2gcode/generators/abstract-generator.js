import XRegExp from 'XRegExp'
XRegExp.install('natives')
// AbstractDriver class
class AbstractGenerator {
  // Class constructor...
  constructor(settings) {
    this.settings = settings;
  }

  postProcessRaster(gcode){
    if (this.settings.gcodeToolOn && this.settings.gcodeToolOff){
      return gcode.replace(new XRegExp("G0(.*?)G1","gis"),'G0$1\n'+this.settings.gcodeToolOn+'\nG1').replace(new XRegExp("G1(.*?)G0","gis"),'G1$1\n'+this.settings.gcodeToolOff+'\nG0')
    }
    return gcode;
  }

}
 
// Exports
export { AbstractGenerator }
export default AbstractGenerator
