# Testing image

<div>
  <img src="https://unsplash.com/photos/lAx4E6Gl06s/download?ixid=MnwxMjA3fDF8MXxhbGx8MXx8fHx8fDJ8fDE2ODEyMjg4NDY&force=true" alt="Image 1" class="image">
  <img src="https://unsplash.com/photos/i6bYNtRNSFo/download?ixid=MnwxMjA3fDB8MXxhbGx8NHx8fHx8fDJ8fDE2ODEyMjg4NDY&force=true" alt="Image 2" class="image">
</div>

<style>
  @media (prefers-color-scheme: dark) {
    .image {
      display: none;
    }
    .image:last-child {
      display: block;
    }
  }
  @media (prefers-color-scheme: light) {
    .image:first-child {
      display: block;
    }
    .image:last-child {
      display: none;
    }
  }
</style>

- Here the dark or light image