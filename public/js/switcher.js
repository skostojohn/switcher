var getUpdate = function(toLoad) {
  var contents = $('#results').text();
  if(contents == '') {
   $("#results").load(toLoad); 
   setTimeout(getUpdate, 4000, toLoad);} 
 }
var displaySpinner = function(toLoad) {
  var opts = {
  lines: 14, // The number of lines to draw
  length: 0, // The length of each line
  width: 10, // The line thickness
  radius: 20, // The radius of the inner circle
  scale: 1.3, // Scales overall size of the spinner
  corners: 0.7, // Corner roundness (0..1)
  color: '#942192', // CSS color or array of colors
  fadeColor: 'transparent', // CSS color or array of colors
  speed: 1, // Rounds per second
  rotate: 4, // The rotation offset
  animation: 'spinner-line-fade-quick', // The CSS animation name for the lines
  direction: 1, // 1: clockwise, -1: counterclockwise
  zIndex: 2e9, // The z-index (defaults to 2000000000)
  className: 'spinner', // The CSS class to assign to the spinner
  top: '50%', // Top position relative to parent
  left: '15%', // Left position relative to parent
  shadow: '0 0 1px transparent', // Box-shadow for the lines
  position: 'absolute' // Element positioning
  };
  var target = document.getElementById('spinner');
  var spinner = new Spinner(opts).spin(target);
  getUpdate(toLoad);
  var target = document.getElementById('results');
  var observer = new MutationObserver(function(mutations) {
    spinner.stop();
    $("#spinner").height(0);   
  });
  var config = { attributes: true, childList: true, characterData: true };
  observer.observe(target, config);
}