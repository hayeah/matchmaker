require 'set'
module MatchMaker
end

class MatchMaker::Case
  class NoMatch < Exception
  end

  class CaseError < RuntimeError
  end
  
  class NoClauses < CaseError
  end
  
  class UnboundVariable < CaseError
  end
  
  class Pattern
    attr_reader :matcher, :guard, :variable
    def initialize(matcher,guard,variable)
      @matcher = matcher # Proc || Pattern
      @guard = guard # Proc || nil
      @variable = variable.to_s.downcase.to_sym if !variable.nil?
    end

    def match(context)
      case @matcher
      when Pattern
        result = @matcher.match(context)
      when Proc
        if @matcher.arity == 2
          result = @matcher.call(context.current,context)
        else
          result = @matcher.call(context.current)
        end
        
      end
      raise NoMatch unless result
      if @guard
        result = @guard.call(context.current)
        raise NoMatch unless result
      end
      context.bind(@variable,context.current) if @variable
      true
    end

    def when(&block)
      @guard = block
      self
    end
  end

  # matches the tail of an array
  class StarPattern # [*pattern]
    attr_reader :pattern, :variable, :guard
    def initialize(pattern,guard,variable)
      @pattern = pattern
      @guard = guard
      @variable = variable
    end
  end

  class MatchContext
    def initialize(object)
      # stack of references we are destructuring,
      # we start off with the object itself.
      @stack = [object]
      @bindings = {}
    end

    def current
      @stack.last
    end

    def bind(var,val)
      if @bindings.has_key?(var)
        raise NoMatch unless @bindings[var] == val
      else
        @bindings[var] = val
      end
    end

    def fail
      raise NoMatch
    end

    unless defined?(BasicObject)
      # for ruby 1.8
      class BasicObject #:nodoc:
        instance_methods.each { |m| undef_method m unless m =~ /^__|instance_eval|object_id/ }
      end
    end
    
    class CallContext < BasicObject
      def initialize(bindings)
        @bindings = bindings
      end

      def method_missing(var,*args)
        ::Kernel.raise ::Case::UnboundVariable.new unless @bindings.has_key?(var)
        @bindings[var]
      end
    end
    

    def call(&block)
      return block.call if @bindings.empty?
      bo = CallContext.new(@bindings)
      bo.instance_eval &block
    end

    def nest(object,pattern=nil)
      @stack.push(object)
      if pattern
        pattern.match(self)
      else
        yield
      end
      @stack.pop
    end
  end

  class Clause
    def initialize(pattern,action)
      raise "badarg" unless Pattern === pattern
      @pattern = pattern
      @action = action
    end

    def match(object)
      context = MatchContext.new(object)
      @pattern.match(context)
      @action.nil? ? true : context.call(&@action)
    end
  end

  def initialize(&block)
    @clauses = []
    self.instance_eval(&block)
    raise NoClauses if @clauses.empty?
    self
  end

  def of(o,&action)
    case o
    when StarPattern
      raise "badarg: star pattern only allowed in structural patterns."
    when Pattern
      pattern = o
    else
      pattern = is(o)
    end
    @clauses << Clause.new(pattern,action)
  end

  # this can be used to coerce literal values into pattern
  def is(o,var=nil,&guard)
    case o
    when Pattern
      #bind(o,var,&guard)
      o # return a is
    when Regexp
      regexp = o
      string(regexp,var,&guard)
    when Array
      array(o,var)
    when Range
      integer(o,var,&guard)
    when Hash
      hash(o,var,&guard)
    when Class
      a(o,var,&guard)
    else
      literal(o,var,&guard)
    end
  end

  def literal(val,var=nil,&guard)
    matcher = lambda { |obj|
      obj == val
    }
    Pattern.new(matcher,guard,var)
  end

  def a(klass,var=nil,&guard)
    # TODO should assert var to be symbol
    matcher = lambda { |o|
      o.is_a?(klass)
    }
    Pattern.new(matcher,guard,var)
  end

  def integer(o=nil,var=nil,&guard)
    case o
    when Integer
      literal(o,var,&guard)
    when Range
      range = o
      matcher_lambda = lambda { |o|
        range.include?(o)
      }
      Pattern.new(matcher_lambda,guard,var)
    when Array
      set = Set.new(o)
      matcher_lambda = lambda { |o|
        set.include?(o)
      }
      Pattern.new(matcher_lambda,guard,var)
    when nil
      a(Integer,var,&guard)
    else
      raise "badarg"
    end
  end

  def symbol(o=nil,var=nil,&guard)
    case o
    when Symbol
      literal(o.to_sym,var,&guard)
    when Regexp
      re = o
      matcher_lambda = lambda { |o|
        o.is_a?(Symbol) && o.to_s =~ re
      }
      Pattern.new(matcher_lambda,guard,var)
    when nil
      a(Symbol,var,&guard)
    else
      raise "badarg"
    end
  end

  def string(o=nil,var=nil,&guard)
    case o
    when String
      literal(o.to_s,var,&guard)
    when Regexp
      re = o
      matcher_lambda = lambda { |o|
        o.is_a?(String) && o.to_s =~ re
      }
      Pattern.new(matcher_lambda,guard,var)
    when nil
      a(String,var,&guard)
    else
      raise "badarg"
    end
  end

  def bind(o,var,&guard)
    Pattern.new(is(o),guard,var)
  end

  def array(os,var=nil,&guard)
    # build structrual pattern
    patterns = os.map { |o|
      case o
      when Pattern, StarPattern
        o
      else
        is(o) # coerce into pattern
      end
    }

    #allow star pattern only for the last position
    star_pattern = nil
    # this works with 1.8.6
    patterns.each_with_index { |pattern,i|
      # allows star pattern only at the end of the pattern
      if pattern.is_a?(StarPattern)
        unless i == patterns.length - 1
          raise "badarg: star pattern only allowed at the end of the array."
        end
        star_pattern = pattern
      end
    }
    if star_pattern
      patterns = patterns[0..-2]
    end
    
    matcher = lambda { |o,context|
      return false unless o.is_a?(Array)
      if star_pattern
        # this is an array pattern with star pattern to match tial
        return false if patterns.length > o.length + 1
      else
        # no star pattern
        return false if patterns.length != o.length
      end
      # match mandatory elements
      patterns.each_with_index { |pattern,i|
        context.nest(o[i],pattern)
      }
      # match tail
      if star_pattern
        tail = o[patterns.size..-1]
        tail.each do |tail_element|
          context.nest(tail_element,star_pattern.pattern)
        end
        return false if star_pattern.guard && star_pattern.guard.call(tail) == false
        context.bind(star_pattern.variable,tail) if star_pattern.variable
      end
      true
    }
    Pattern.new(matcher,guard,var)
  end

  # ["key"] => optional key
  ## /regexp/ => across all key that matches
  # literal => required key
  # bleh..
  def hash(hash=nil,var=nil,&guard)
    # coerce literals into patterns
    patterns = hash.to_a.map! { |(k,v)|
      [k,(v.is_a?(Pattern) ? v : is(v))]
    }
    matcher = lambda { |h,context|
      context.fail unless h.is_a?(Hash)
      patterns.each { |(k,value_pattern)|
        case k
        when Array
          # optional key
          k = k.first
          # try matching iff the value is non-nil
          context.nest(h[k],value_pattern) if value=h[k]
          # regexp match is a bit silly...
        # when Regexp
#           # pattern applies to all keys that matches regexp
#           re = k
#           hash.keys.each do |k|
#             if k =~ re
#               context.nest(h[k],value_pattern)
#             end
#           end
          
        else
          # required key
          context.fail unless h.has_key?(k)
          context.nest(h[k],value_pattern)
        end
      }
      true
    }
    Pattern.new(matcher,guard,var)
  end

  def _(var=nil,&guard)
    matcher = lambda { |o| true }
    Pattern.new(matcher, guard, var)
  end

  def _!(pattern,var=nil,&guard)
    pattern = is(pattern) unless Pattern === pattern
    StarPattern.new(pattern,guard,var)
  end
  
  def match(o)
    @clauses.each { |c|
      begin
        return c.match(o)
      rescue NoMatch
      end
    }
    raise NoMatch
  end

  def to_s
    "#<#{self.class}>"
  end

  def inspect
    self.to_s
  end
end

Case = MatchMaker::Case

def Case(obj,&block)
  Case.new(&block).match(obj)
end

