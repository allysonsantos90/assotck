document.getElementById("year").textContent = new Date().getFullYear();
const toggle = document.querySelector(".menu-toggle");
const nav = document.querySelector(".nav");
toggle.addEventListener("click", () => {
  const open = nav.classList.toggle("open");
  toggle.setAttribute("aria-expanded", String(open));
});
nav.querySelectorAll("a").forEach(link => link.addEventListener("click", () => {
  nav.classList.remove("open");
  toggle.setAttribute("aria-expanded", "false");
}));

/*
  VIDEO LINKS:
  Replace the placeholder URLs below with your own public YouTube or Vimeo links.
  For a direct video embed, use the embed URL (YouTube: https://www.youtube.com/embed/VIDEO_ID
  Vimeo: https://player.vimeo.com/video/VIDEO_ID).
  The portfolio cards currently lead to the contact section until you add your links.
*/
const videoLinks = {
  preview: "",
  "getting-ready": "",
  ceremony: "",
  vows: "",
  reception: ""
};

document.querySelectorAll("[data-video]").forEach(card => {
  const url = videoLinks[card.dataset.video];
  if (url) card.href = url;
  card.addEventListener("click", event => {
    if (!videoLinks[card.dataset.video]) {
      event.preventDefault();
      alert("Add your YouTube or Vimeo video link in script.js to activate this portfolio item.");
    }
  });
});
