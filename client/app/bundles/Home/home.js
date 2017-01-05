import Bowser from 'bowser';
import Tabslet from 'tabslet';
import $ from 'jquery'
require('../../assets/styles/home.scss')
require('./bootstrap_carousel.js')

console.log('Hi from home bundle!');

// var d = document.getElementsByTagName("body");
// console.log("d: ", JSON.stringify(d));
// if (Bowser.safari) {
//   console.log("I'm in safari: ", d)
//   d.className += " bow-safari";
// } else if (Bowser.chrome) {
//   console.log("I'm in chrome", d)
//   d[0].className += " bow-chrome";
// } else if (Bowser.firefox) {
//   console.log("I'm in firefox", d)
//   d.className += " bow-firefox";
// }

document.onreadystatechange = function () {
  var state = document.readyState;
  if (state == 'interactive') {
    console.log('init')
  } else if (state == 'complete') {
    setBrowserClass();
  }

  $('tabs-teacher-stories').tabslet({
    autorotate: true,
    delay: 10000,
    pauseonhover: true,
    animation: true,
    active: 1
  });

  $('.tabs-testimonials').tabslet({
    autorotate: true,
    delay: 10000,
    pauseonhover: false,
    animation: true,
    active: 1
  });
};

function setBrowserClass() {
  var d = document.getElementsByTagName('body');
  if (Bowser.safari) {
    d[0].className += ' bow-safari';
  } else if (Bowser.chrome) {
    d[0].className += ' bow-chrome';
  } else if (Bowser.firefox) {
    d[0].className += ' bow-firefox';
  }
}