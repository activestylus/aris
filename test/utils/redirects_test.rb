# test/utils/redirects_test.rb
require_relative '../test_helper'
require_relative '../../lib/aris/utils/redirects'

class RedirectsUtilTest < Minitest::Test
  def setup
    Aris::Utils::Redirects.reset!
  end

  def teardown
    Aris::Utils::Redirects.reset!
  end

  def test_register_single_redirect
    Aris::Utils::Redirects.register(
      from_paths: '/old-path',
      to_path: '/new-path'
    )

    redirect = Aris::Utils::Redirects.find('/old-path')
    assert_equal '/new-path', redirect[:to]
    assert_equal 301, redirect[:status]
  end

  def test_register_multiple_redirects
    Aris::Utils::Redirects.register(
      from_paths: ['/old-1', '/old-2'],
      to_path: '/new-path'
    )

    assert_equal '/new-path', Aris::Utils::Redirects.find('/old-1')[:to]
    assert_equal '/new-path', Aris::Utils::Redirects.find('/old-2')[:to]
  end

  def test_custom_status_code
    Aris::Utils::Redirects.register(
      from_paths: '/temp',
      to_path: '/new',
      status: 302
    )

    redirect = Aris::Utils::Redirects.find('/temp')
    assert_equal 302, redirect[:status]
  end

  def test_find_returns_nil_for_unknown_path
    assert_nil Aris::Utils::Redirects.find('/unknown')
  end

  def test_all_returns_redirect_map
    Aris::Utils::Redirects.register(from_paths: '/a', to_path: '/b')
    Aris::Utils::Redirects.register(from_paths: '/c', to_path: '/d')

    all = Aris::Utils::Redirects.all
    assert_equal 2, all.size
    assert all.key?('/a')
    assert all.key?('/c')
  end
end