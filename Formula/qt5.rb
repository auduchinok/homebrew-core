class OracleHomeVarRequirement < Requirement
  fatal true
  satisfy(:build_env => false) { ENV["ORACLE_HOME"] }

  def message; <<-EOS.undent
      To use --with-oci you have to set the ORACLE_HOME environment variable.
      Check Oracle Instant Client documentation for more information.
    EOS
  end
end

# Patches for Qt5 must be at the very least submitted to Qt's Gerrit codereview
# rather than their bug-report Jira. The latter is rarely reviewed by Qt.
class Qt5 < Formula
  desc "Version 5 of the Qt framework"
  homepage "https://www.qt.io/"
  url "https://download.qt.io/official_releases/qt/5.6/5.6.1/single/qt-everywhere-opensource-src-5.6.1.tar.xz"
  mirror "https://www.mirrorservice.org/sites/download.qt-project.org/official_releases/qt/5.6/5.6.1/single/qt-everywhere-opensource-src-5.6.1.tar.xz"
  sha256 "0d3cc75d2368ad988c9ec6bcbed6362dbaa8e03fdfd04e679284f4b9af91e565"

  head "https://code.qt.io/qt/qt5.git", :branch => "5.6", :shallow => false

  bottle do
    sha256 "e33fe196cfc3997a3620be91e52a2e3378bc140ca2a17a84a6de769d77a96b9b" => :el_capitan
    sha256 "721d7569b6880b31bd7ab684773f40ee147b3ea2ee9c6f0b81eb71d99ace90dd" => :yosemite
    sha256 "76b0e2a980326bf520e0f1405132928eec91f68547602e562d81e4690e6a3b27" => :mavericks
  end

  # Restore `.pc` files for framework-based build of Qt 5 on OS X. This
  # partially reverts <https://codereview.qt-project.org/#/c/140954/> merged
  # between the 5.5.1 and 5.6.0 releases. (Remove this as soon as feasible!)
  #
  # Core formulae known to fail without this patch (as of 2016-03-17):
  #   * mkvtoolnix (with `--with-qt5` option, silent build failure)
  #   * poppler    (with `--with-qt5` option)
  #   * wireshark  (with `--with-qt5` option)
  patch do
    url "https://raw.githubusercontent.com/Homebrew/formula-patches/e8fe6567/qt5/restore-pc-files.patch"
    sha256 "48ff18be2f4050de7288bddbae7f47e949512ac4bcd126c2f504be2ac701158b"
  end

  keg_only "Qt 5 conflicts Qt 4 (which is currently much more widely used)."

  option "with-docs", "Build documentation"
  option "with-examples", "Build examples"
  option "with-oci", "Build with Oracle OCI plugin"

  option "without-webengine", "Build without QtWebEngine module"

  deprecated_option "qtdbus" => "with-dbus"
  deprecated_option "with-d-bus" => "with-dbus"

  # OS X 10.7 Lion is still supported in Qt 5.5, but is no longer a reference
  # configuration and thus untested in practice. Builds on OS X 10.7 have been
  # reported to fail: <https://github.com/Homebrew/homebrew/issues/45284>.
  depends_on :macos => :mountain_lion

  depends_on "dbus" => :optional
  depends_on :mysql => :optional
  depends_on :postgresql => :optional
  depends_on :xcode => :build

  depends_on OracleHomeVarRequirement if build.with? "oci"

  def install
    args = %W[
      -verbose
      -prefix #{prefix}
      -release
      -opensource -confirm-license
      -system-zlib
      -qt-libpng
      -qt-libjpeg
      -qt-freetype
      -qt-pcre
      -nomake tests
      -no-rpath
    ]

    args << "-nomake" << "examples" if build.without? "examples"

    args << "-plugin-sql-mysql" if build.with? "mysql"
    args << "-plugin-sql-psql" if build.with? "postgresql"

    if build.with? "dbus"
      dbus_opt = Formula["dbus"].opt_prefix
      args << "-I#{dbus_opt}/lib/dbus-1.0/include"
      args << "-I#{dbus_opt}/include/dbus-1.0"
      args << "-L#{dbus_opt}/lib"
      args << "-ldbus-1"
      args << "-dbus-linked"
    else
      args << "-no-dbus"
    end

    if build.with? "oci"
      args << "-I#{ENV["ORACLE_HOME"]}/sdk/include"
      args << "-L#{ENV["ORACLE_HOME"]}"
      args << "-plugin-sql-oci"
    end

    args << "-skip" << "qtwebengine" if build.without? "webengine"

    system "./configure", *args
    system "make"
    ENV.j1
    system "make", "install"

    if build.with? "docs"
      system "make", "docs"
      system "make", "install_docs"
    end

    # Some config scripts will only find Qt in a "Frameworks" folder
    frameworks.install_symlink Dir["#{lib}/*.framework"]

    # The pkg-config files installed suggest that headers can be found in the
    # `include` directory. Make this so by creating symlinks from `include` to
    # the Frameworks' Headers folders.
    Pathname.glob("#{lib}/*.framework/Headers") do |path|
      include.install_symlink path => path.parent.basename(".framework")
    end

    # configure saved PKG_CONFIG_LIBDIR set up by superenv; remove it
    # see: https://github.com/Homebrew/homebrew/issues/27184
    inreplace prefix/"mkspecs/qconfig.pri",
              /\n# pkgconfig\n(PKG_CONFIG_(SYSROOT_DIR|LIBDIR) = .*\n){2}\n/,
              "\n"

    # Move `*.app` bundles into `libexec` to expose them to `brew linkapps` and
    # because we don't like having them in `bin`. Also add a `-qt5` suffix to
    # avoid conflict with the `*.app` bundles provided by the `qt` formula.
    # (Note: This move/rename breaks invocation of Assistant via the Help menu
    # of both Designer and Linguist as that relies on Assistant being in `bin`.)
    libexec.mkpath
    Pathname.glob("#{bin}/*.app") do |app|
      mv app, libexec/"#{app.basename(".app")}-qt5.app"
    end
  end

  def caveats; <<-EOS.undent
    We agreed to the Qt opensource license for you.
    If this is unacceptable you should uninstall.
    EOS
  end

  test do
    (testpath/"hello.pro").write <<-EOS.undent
      QT       += core
      QT       -= gui
      TARGET = hello
      CONFIG   += console
      CONFIG   -= app_bundle
      TEMPLATE = app
      SOURCES += main.cpp
    EOS

    (testpath/"main.cpp").write <<-EOS.undent
      #include <QCoreApplication>
      #include <QDebug>

      int main(int argc, char *argv[])
      {
        QCoreApplication a(argc, argv);
        qDebug() << "Hello World!";
        return 0;
      }
    EOS

    system bin/"qmake", testpath/"hello.pro"
    system "make"
    assert File.exist?("hello")
    assert File.exist?("main.o")
    system "./hello"
  end
end
