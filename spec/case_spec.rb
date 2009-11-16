require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe Case do
  def not_match
    raise_error(Case::CaseFail)
  end

  def be_unbound
    raise_error(Case::UnboundVariable)
  end

  TEST_CONSTANT_1 = :test_constant_1
  it "DSL should preserve module nesting of original block" do
    pending
    Case(1) {
      of(1) { TEST_CONSTANT_1 }
    }.should == TEST_CONSTANT_1
  end

  it "should make a pattern object" do
    pat = Case.pattern {
      [:a,integer,string]
    }
    pat.should be_a(Case::Pattern)
    Case([:a,10,"abc"]) {
      of(pat)
    }.should == true
  end

  it "should pattern match with shortcut" do
    Case("a") {
      of "a"
    }.should == true
    lambda {
      Case("a") {
      of 1
      }
    }.should not_match
  end

  it "should not allow star pattern except in structural patterns" do
    lambda {
      Case.new {
      }
    }.should raise_error
  end

  it "should not be used with no clauses" do
    lambda { Case.new { } }.should raise_error(Case::NoClauses)
  end
  
  it "should build case object with clauses" do
    Case.new do
      of 1
      of 2
    end.should be_a(Case)
  end

  it "should build star pattern" do
    star_pattern, literal_pattern = nil
    Case.new {
      literal_pattern = literal(3)
      star_pattern = _!(literal_pattern)
    } rescue Case::NoClauses
    star_pattern.should be_a(Case::StarPattern)
    star_pattern.pattern.should == literal_pattern
  end

  it "should return true for matched pattern (without action)" do
    c = Case.new do
      of 1
      of :a
    end
    c.match(1).should == true
    lambda { c.match(2) }.should not_match
    c.match(:a).should == true
    lambda { c.match(:b) }.should not_match
  end

  it "should return value of pattern matched action" do
    c = Case.new do
      of(1) { [1] }
      of(:a) { [:a] }
      of(:b) { throw(:throw_test) }
    end
    c.match(1).should == [1]
    c.match(:a).should == [:a]
    lambda { c.match(:b) }.should throw_symbol(:throw_test)
  end

  it "should throw error for unbound variable" do
    c = Case.new do
      of(literal(1,:a)) { b }
    end
    lambda { c.match(1) }.should be_unbound
  end

  it "should create binding for matched variable" do
    c = Case.new do
      of(literal(1,:a)) { a }
    end
    c.match(1).should == 1
  end

  it "should scope bindings"

  it "should downcase symbol for variable binding" do
    c = Case.new do
      of(literal(1,:A)) { a }
    end
    c.match(1).should == 1
  end
  
  it "should bind to the same variable iff the values are equal" do
    c = Case.new do
      of([is(1,:a),is(1,:a)])
      of([is(2,:A),is(1,:A)])
      of([is(3,:B),is(3,:b)])
    end
    c.match([1,1]).should == true
    lambda { c.match([2,1]) }.should not_match
    c.match([3,3]).should == true
  end

  describe "guard" do
    it "should add guard with the Pattern#when" do
      c = Case.new do
        of(literal(1).when{|o| false})
        of(literal(2))
      end
      lambda { c.match(1) }.should not_match
      c.match(2).should == true
    end
    
    it "should fail pattern if guard fails" do
      c = Case.new do
        of(literal(1){|o| false})
        of(literal(2))
      end
      lambda { c.match(1) }.should not_match
      c.match(2).should == true
    end
  end

  describe "literal pattern" do
    it "should match literal by object equality" do
      o1 = Object.new
      o2 = Object.new
      c = Case.new do
        of o1
      end
      c.match(o1).should == true
      lambda { c.match(o2) }.should not_match
    end
  end

  describe "class pattern" do
    it "should match objects of a class" do
      s1 = "a"
      s2 = "b"
      c = Case.new do
        of(a(String))
      end
      c.match(s1).should == true
      c.match(s2).should == true
    end

    it "should use guard" do
      c = Case.new do
        of(a(Integer))
        of(a(String) { false })
      end
      c.match(1).should == true
      lambda { c.match("a") }.should not_match
    end
  end

  describe "integer pattern" do
    it "should match a range" do
      c = Case.new do
        of(integer(1..100){ |i| i % 2 == 0}) 
      end
      c.match(2).should == true
      c.match(100).should == true
      lambda { c.match(1)}.should not_match
      lambda { c.match(0)}.should not_match
      lambda { c.match(102)}.should not_match
    end

    it "should match a set" do
      c = Case.new do
        of integer([2,100])
      end
      c.match(2).should == true
      c.match(100).should == true
      lambda { c.match(1)}.should not_match
      lambda { c.match(0)}.should not_match
      lambda { c.match(102)}.should not_match
    end

    it "should match any integer" do
      c = Case.new do
        of(integer)
      end
      c.match(2).should == true
      c.match(100).should == true
      lambda { c.match(:foo)}.should not_match
    end
  end

  describe "symbol pattern" do
    it "should match symbol by regexp" do
      c = Case.new do
        of(symbol(/^a.*/))
      end
      c.match(:a).should == true
      c.match(:abc).should == true
      lambda { c.match(:babc) }.should not_match
      lambda { c.match(10) }.should not_match
    end

    it "should match a symbol by class, string, or symbol" do
      c = Case.new do
        of(symbol { |o| o.to_s.length == 1})
        of(symbol(:ab,:AB)) { ab }
      end
      c.match(:a).should == true
      lambda { c.match(1) }.should not_match
      c.match(:ab).should == :ab
      lambda { c.match(:bc) }.should not_match
    end

    it "should use guards" do
      c = Case.new do
        of(symbol { |o| false })
        of(symbol(:a) { |o| false })
        of(symbol(/.*/) { |o| false })
      end
      lambda { c.match(:b) }.should not_match
      lambda { c.match(:a) }.should not_match
      lambda { c.match(:faewfe) }.should not_match
    end
  end

  describe "string pattern" do
    it "should match string by regexp" do
      c = Case.new do
        of(string(/^a.*/))
      end
      c.match("a").should == true
      c.match("abc").should == true
      lambda { c.match("babc") }.should not_match
      lambda { c.match(10) }.should not_match
    end

    it "should match a string by class, string, or symbol" do
      c = Case.new do
        of(string { |o| o.to_s.length == 1}) 
        of(string("ab",:AB)) { ab }
      end
      c.match("a").should == true
      lambda { c.match(1) }.should not_match
      lambda { c.match("abc") }.should not_match
      c.match("ab").should == "ab"
      lambda { c.match("bc") }.should not_match
    end

    it "should use guards" do
      c = Case.new do
        of(string { |o| false })
        of(string("a") { |o| false })
        of(string(/.*/) { |o| false })
      end
      lambda { c.match("a") }.should not_match
      lambda { c.match("abc") }.should not_match
      lambda { c.match("abcde") }.should not_match
    end
  end
  
  describe "bind pattern" do
    it "should bind a pattern to a variable" do
      c = Case.new do
        sym = a(Symbol)
        of(bind(sym,:A){|o| o == :foo }) { a }
        of(bind(sym,:A){|o| o == :bar }) { a }
      end
      c.match(:foo).should == :foo
      c.match(:bar).should == :bar
      lambda { c.match(:qux) }.should not_match
    end
  end

  describe "is pattern" do
    it "should make range a integer range pattern" do
      c = Case.new do
        of(1..100)
      end
      c.match(1).should == true
      c.match(100).should == true
      lambda { c.match(0) }.should not_match
      lambda { c.match(101) }.should not_match
    end

    it "should make array an array pattern" do
      c = Case.new do
        of([1,2])
      end
      c.match([1,2]).should == true
    end

    it "should make regexp a string pattern" do
      c = Case.new do
        of(/abc/)
      end
      c.match("0abc0").should == true
    end

    it "should make hash a hash pattern" do
      c = Case.new do
        of(:a => 1)
      end
      c.match(:a => 1).should == true
    end

    it "should make class a class pattern" do
      c = Case.new do
        of(String)
      end
      c.match("abc").should == true
    end
  end

  describe "wildcard pattern" do
    it "should match anything" do
      c = Case.new do
        of(_(:V) { |o| o != :foobarqux }) {
          v
        }
      end
      c.match(10).should == 10
      c.match(:a).should == :a
      c.match("a").should == "a"
      c.match(Object.new).should be_a(Object)
      lambda { c.match(:foobarqux) }.should not_match
    end
  end

  describe "one_of pattern" do
    it "matches one_of a number of patterns" do
      c = Case.new do
        of(one_of([1,"b"],:V)) {
          v
        }
      end
      c.match(1).should == 1
      c.match("b").should == "b"
      lambda { c.match("c") }.should not_match
    end
  end

  describe "array pattern" do
    it "should match the exact length of array" do
      c = Case.new {
        of [1,2,3]
      }
      c.match([1,2,3]).should == true
      lambda { c.match([]) }.should not_match
      lambda { c.match([1,2]) }.should not_match
      lambda { c.match([1,2,3,4]) }.should not_match
    end

    it "should use guard" do
      c = Case.new {
        of(array([1,2,3]){ false })
      }
      lambda { c.match([1,2,3]) }.should not_match
    end

    it "should match patterns in array pattern" do
      c = Case.new {
        pattern = symbol(/^a.*/)
        of([pattern,pattern,pattern]) { 2 }
        of([])  { 1 }
      }
      c.match([]).should == 1
      c.match([:a,:ab,:abc]).should == 2
      lambda { c.match([:a,:ab,:abc,:abcd]) }.should not_match
    end

    it "should match tail" do
      c = Case.new {
        of([_!(1)])
      }
      c.match([]).should == true
      c.match([1,1]).should == true
      c.match([1,1,1]).should == true
      c.match([1,1,1,1]).should == true
    end

    it "should bind tail" do
      c = Case.new {
        of([_!(1,:tail)]) { tail }
      }
      c.match([]).should == []
      c.match([1,1]).should == [1,1]
    end

    it "should match heads then tail" do
      c = Case.new {
        of([:a,:b,:c,_!(1,:tail)]) { tail }
      }
      c.match([:a,:b,:c]).should == []
      c.match([:a,:b,:c,1]).should == [1]
      c.match([:a,:b,:c,1,1]).should == [1,1]
      lambda { c.match([:a,:b,1,1,1,1,1]) }.should not_match
      lambda { c.match([1,1,1,1,1]) }.should not_match
      lambda { c.match([:a,:b,:c,1,2]) }.should not_match
    end

    it "should use guard in tail pattern" do
      c = Case.new {
        of [_!(1){ |o| false }]
        of [_!(integer(){ |o| o % 2 == 0 }){ |tail| tail.length == 3 }]
      }
      lambda {c.match([1,1,1])}.should not_match
      lambda {c.match([2,2,1])}.should not_match
      c.match([2,2,2]).should == true
      c.match([2,4,6]).should == true
      lambda {c.match([2,4,6,8])}.should not_match
    end

    it "should match nested arrays" do
      c = Case.new {
        of [1,2,[3,4,_!(symbol)]]
      }
      c.match([1,2,[3,4,:a,:b,:c]]).should == true
      c.match([1,2,[3,4]]).should == true
      lambda { c.match([1,2,[3,4,5,6,7]]) }.should not_match
      lambda { c.match([1,2,[3]]) }.should not_match
      lambda { c.match([1,2]) }.should not_match
    end
  end

  describe "hash pattern" do
    it "should match required keys" do
      c = Case.new {
        of(hash(:a => 1, :b => 2))
      }
      c.match(:a => 1, :b => 2).should == true
      c.match(:a => 1, :b => 2, :c => 3).should == true
      lambda { c.match(1) } .should not_match
      lambda { c.match(:a => 1, :b => 3) }.should not_match
      lambda { c.match(:a => 1, :c => 3) }.should not_match
    end
    
    it "should match optional keys" do
      c = Case.new {
        of(hash([:a] => 1))
      }
      c.match(:a => 1).should == true
      c.match(:a => nil).should == true
      c.match({}).should == true
      lambda { c.match(:a => 2)}.should not_match
    end
  end
end
