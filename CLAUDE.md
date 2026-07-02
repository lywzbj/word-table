# CLAUDE.md

## 项目概述
本项目是一个基于 Java 17 的 Word 文档渲染引擎，使用 Apache POI 生成和操作 .docx 文件。  
主要功能包括：
- 从 DOCX 模板渲染数据（占位符替换）
- 动态创建表格、段落、图片
- 支持页眉/页脚/水印
- 输出为字节流或保存到文件

## 构建与常用命令
- 编译: `mvn clean compile`
- 运行测试: `mvn test`
- 打包为可执行 JAR: `mvn package -DskipTests`
- 依赖树: `mvn dependency:tree`


## 技术栈
- **Java 17** — 允许使用 Records、Switch 表达式、文本块、增强型 instanceof、Sealed Classes（如需要）
- **Maven 3.8+** — 依赖管理与构建
- **Apache POI 5.2.5** — 核心文档处理
    - `poi-ooxml`（包含 XWPF 相关类）
    - `poi-ooxml-schemas`（OOXML schema）
    - （可选）`poi-scratchpad` 如果你需要 HWPF（旧版.doc）
- **日志**: SLF4J 2.x + Logback 1.4.x
- **测试**: JUnit 5 + AssertJ + Mockito（按需引入）

## 编码规范与注意事项
- **命名**：遵循 Java 标准命名（类 PascalCase，方法/变量 camelCase，常量 UPPER_SNAKE）
- **异常处理**：使用自定义业务异常包装 POI 的底层异常，不允许直接吞掉异常
- **资源管理**：所有 `InputStream` / `OutputStream` / `XWPFDocument` 必须用 try-with-resources 确保关闭
- **Javadoc**：所有 public 方法需书写完整的中文或英文文档注释，说明参数、返回值和可能抛出的异常
- **日志**：关键步骤（模板加载、渲染开始/结束、异常）输出 INFO 或 ERROR 日志，避免在循环内频繁打印 DEBUG
- **不可变数据**：优先使用 `record` 定义数据传输对象（DTO）
- **单元测试**：
    - 渲染结果必须通过断言验证文档结构（如段落数、表格行数）和文本内容
    - 使用 `src/test/resources` 下的模板文件进行测试
    - 覆盖正常路径和异常路径（如模板不存在、占位符缺失）
- **避免使用已弃用的 API**：
    - 只处理 `.docx`（XWPF），不使用 HSSF / HWPF（除非明确需要兼容旧格式）
    - 用 `XWPFDocument` 而非旧的 `HWPFDocument`
    - 样式设置优先使用 `XWPFStyles` 或自定义 `CT…` 类，而不是直接字符串拼接

## Apache POI 特定指南
- **占位符替换**：遍历所有 `XWPFParagraph` 和 `XWPFRun`，在 `XWPFRun` 的 `text()` 中执行字符串替换。注意一个占位符可能被拆分到多个 run，需要先合并相邻 run 再替换
- **表格处理**：通过 `XWPFTable` 操作行列，注意 POI 中单元格内段落需要单独创建和添加
- **图片插入**：使用 `XWPFRun.addPicture()`，图片格式推荐 PNG，需计算合适的尺寸（EMU 单位）
- **中文字体**：为 runs 设置字体（如 `宋体`、`黑体`）时，使用 `setFontFamily("宋体")` 并在模板或样式中保证字体可用
- **模板存放**：所有 DOCX 模板放在 `src/main/resources/templates/`，代码中使用 `ClassLoader.getResourceAsStream()` 加载
- **输出**：如果需要将生成的文档写入 HTTP 响应，直接 `XWPFDocument.write(OutputStream)`，并在 finally 中关闭文档

## 示例依赖（pom.xml 片段）
```xml
<properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
    <poi.version>5.2.5</poi.version>
    <slf4j.version>2.0.9</slf4j.version>
</properties>

<dependencies>
    <dependency>
        <groupId>org.apache.poi</groupId>
        <artifactId>poi-ooxml</artifactId>
        <version>${poi.version}</version>
    </dependency>
    <dependency>
        <groupId>org.apache.poi</groupId>
        <artifactId>poi-ooxml-schemas</artifactId>
        <version>${poi.version}</version>
    </dependency>
    <dependency>
        <groupId>org.slf4j</groupId>
        <artifactId>slf4j-api</artifactId>
        <version>${slf4j.version}</version>
    </dependency>
    <dependency>
        <groupId>ch.qos.logback</groupId>
        <artifactId>logback-classic</artifactId>
        <version>1.4.14</version>
        <scope>runtime</scope>
    </dependency>

    <!-- 测试 -->
    <dependency>
        <groupId>org.junit.jupiter</groupId>
        <artifactId>junit-jupiter</artifactId>
        <version>5.10.1</version>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.assertj</groupId>
        <artifactId>assertj-core</artifactId>
        <version>3.24.2</version>
        <scope>test</scope>
    </dependency>
</dependencies>
```
