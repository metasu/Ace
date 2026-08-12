# WordPress 嵌入教程

---

## 一、B站视频嵌入

将 `aid=数字` 替换为B站视频的 AV 号（BV 号需先转换）。

```
<iframe id="spkj" src="https://player.bilibili.com/player.html?aid=替换为AV号&page=1"
 width="100%" frameborder="no" scrolling="no" allowfullscreen="allowfullscreen">
</iframe>
<script type="text/javascript">
  document.getElementById("spkj").style.height = document.getElementById("spkj").scrollWidth * 0.5625 + "px";
</script>
```

---

## 二、视频嵌入

```
<video controls style="width: 100%; height: auto; border-radius: 0.5rem;" src="https://example.com/video.mp4"></video>
```

---

## 三、音乐嵌入

```
<audio controls style="display:block;width:50%;margin:0 auto;" src="https://example.com/audio.mp3"></audio>
```

---

## 四、图片嵌入

```
<div style="text-align:center;"><img src="https://example.com/image.jpg" width="80%"></div>
```

### 多图片紧凑布局

```
<div class="name-strip">
  <img src="https://example.com/image1.jpg">
  <img src="https://example.com/image2.jpg">
  <img src="https://example.com/image3.jpg">
</div>
```

配套 CSS（添加到主题样式表）：

```
.name-strip {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}
.name-strip img {
  flex: 1 1 auto;
  max-width: 100%;
  height: auto;
}
```

---

## 五、链接嵌入

```
<a href="https://example.com" target="_blank" rel="noopener">链接文字</a>
```
